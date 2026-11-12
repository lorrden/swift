; RUN: %clang-no-modules -target arm64-apple-macos13 -O2 -Wno-override-module -S -x ir %s -o - | %FileCheck %s
; RUN: %target-clang -O2 -Wno-override-module -x ir %s -o %t
; RUN: %target-run %t
;
; REQUIRES: CPU=arm64, OS=macosx, executable_test
;
; Reference LLVM lowering for a direct-threaded runner. Two dispatch sites
; share a prepared stream and the same physical handler landing blocks.
; The hot path reads a prepared address and advances the VM PC.

@labels = private constant [3 x ptr] [
  ptr blockaddress(@run, %increment),
  ptr blockaddress(@run, %double),
  ptr blockaddress(@run, %halt)
]

; Check a hot-loop target load and its branch. Allow the PC update to be
; scheduled between the load and branch, and allow shared dispatch.
; CHECK-LABEL: _run:
; CHECK-NOT: {{[[:space:]]bl(r)?[[:space:]]}}
; CHECK: Inner Loop Header
; CHECK-NOT: {{[[:space:]]bl(r)?[[:space:]]}}
; CHECK: ldr [[TARGET:x[0-9]+]], [
; CHECK-NOT: {{[[:space:]](ldr|bl|blr)[[:space:]]}}
; CHECK: br [[TARGET]]
; CHECK-NOT: {{[[:space:]]bl(r)?[[:space:]]}}
; CHECK: ret
define i32 @run(ptr %code) noinline {
entry:
  %thread = alloca [3 x ptr]
  %pc = alloca i64
  %acc = alloca i32
  store i64 0, ptr %pc
  store i32 1, ptr %acc
  br label %prepare

prepare:
  %i = phi i64 [ 0, %entry ], [ %next, %write ]
  %opcode.cell = getelementptr i32, ptr %code, i64 %i
  %opcode = load i32, ptr %opcode.cell
  %valid.opcode = icmp ult i32 %opcode, 3
  br i1 %valid.opcode, label %write, label %invalid

write:
  %slot = zext i32 %opcode to i64
  %label.cell = getelementptr [3 x ptr], ptr @labels, i64 0, i64 %slot
  %label = load ptr, ptr %label.cell
  %thread.cell = getelementptr [3 x ptr], ptr %thread, i64 0, i64 %i
  store ptr %label, ptr %thread.cell
  %next = add i64 %i, 1
  %ready = icmp eq i64 %next, 3
  br i1 %ready, label %dispatch, label %prepare

increment:
  %before.increment = load i32, ptr %acc
  %incremented = add i32 %before.increment, 1
  store i32 %incremented, ptr %acc
  br label %dispatch

double:
  %before.double = load i32, ptr %acc
  %doubled = shl i32 %before.double, 1
  store i32 %doubled, ptr %acc
  %double.pc = load i64, ptr %pc
  %valid.double.pc = icmp ult i64 %double.pc, 3
  br i1 %valid.double.pc, label %after.double, label %invalid

after.double:
  %after.double.pc = add i64 %double.pc, 1
  store i64 %after.double.pc, ptr %pc
  %double.cell = getelementptr [3 x ptr], ptr %thread, i64 0, i64 %double.pc
  %double.target = load ptr, ptr %double.cell
  indirectbr ptr %double.target, [label %increment, label %double, label %halt]

dispatch:
  %index = load i64, ptr %pc
  %valid.pc = icmp ult i64 %index, 3
  br i1 %valid.pc, label %lookup, label %invalid

lookup:
  %next.pc = add i64 %index, 1
  store i64 %next.pc, ptr %pc
  %cell = getelementptr [3 x ptr], ptr %thread, i64 0, i64 %index
  %target = load ptr, ptr %cell
  indirectbr ptr %target, [label %increment, label %double, label %halt]

halt:
  %result = load i32, ptr %acc
  ret i32 %result

invalid:
  call void @llvm.trap()
  unreachable
}

declare void @llvm.trap()

@increment_then_double = private constant [3 x i32] [i32 0, i32 1, i32 2]
@double_then_increment = private constant [3 x i32] [i32 1, i32 0, i32 2]

define i32 @main() {
  %first = call i32 @run(ptr @increment_then_double)
  %second = call i32 @run(ptr @double_then_increment)
  %first.correct = icmp eq i32 %first, 4
  %second.correct = icmp eq i32 %second, 3
  %correct = and i1 %first.correct, %second.correct
  %status = select i1 %correct, i32 0, i32 1
  ret i32 %status
}
