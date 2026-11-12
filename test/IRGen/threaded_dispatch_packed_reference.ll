; REQUIRES: CPU=arm64, OS=macosx, executable_test
;
; RUN: %clang-no-modules -target arm64-apple-macos13 -O2 -Wno-override-module -S -x ir %s -o - | %FileCheck %s
; RUN: %target-clang -O2 -Wno-override-module -x ir %s -o %t
; RUN: %target-run %t
;
; The opcode table contains full addresses. Preparation packs the checked
; signed displacement from @run into the low half of each program word and
; copies the operand into the high half. Both calls execute the same buffer.
;
; CHECK-LABEL: _run:
; CHECK: {{; %dispatch[[:space:]]*$}}
; CHECK-NEXT: ldr x[[WORD:[0-9]+]], [
; CHECK-NEXT: add [[TARGET:x[0-9]+]], {{x[0-9]+}}, w[[WORD]], sxtw
; CHECK-NEXT: lsr {{x[0-9]+}}, x[[WORD]], #32
; CHECK-NOT: {{[[:space:]](ldr|bl|blr)[[:space:]]}}
; CHECK: br [[TARGET]]

@labels = private constant [2 x ptr] [
  ptr blockaddress(@run, %add),
  ptr blockaddress(@run, %xor)
]

define internal i64 @run(ptr %source, ptr %program, i64 %count, i1 %prepare) noinline nooutline {
entry:
  %empty = icmp eq i64 %count, 0
  br i1 %empty, label %empty.result, label %mode

mode:
  br i1 %prepare, label %decode, label %dispatch

decode:
  %index = phi i64 [ 0, %mode ], [ %next, %pack ]
  %source.cell = getelementptr inbounds i64, ptr %source, i64 %index
  %instruction = load i64, ptr %source.cell, align 8
  %opcode = trunc i64 %instruction to i32
  %valid = icmp ult i32 %opcode, 2
  br i1 %valid, label %lookup, label %invalid

lookup:
  %slot = zext i32 %opcode to i64
  %label.cell = getelementptr inbounds [2 x ptr], ptr @labels, i64 0, i64 %slot
  %label = load ptr, ptr %label.cell, align 8
  %address = ptrtoint ptr %label to i64
  %difference = sub i64 %address, ptrtoint (ptr @run to i64)
  %offset = trunc i64 %difference to i32
  %roundtrip = sext i32 %offset to i64
  %fits = icmp eq i64 %difference, %roundtrip
  br i1 %fits, label %pack, label %invalid

pack:
  %operand.bits = and i64 %instruction, -4294967296
  %offset.bits = zext i32 %offset to i64
  %packed = or i64 %operand.bits, %offset.bits
  %output.cell = getelementptr inbounds i64, ptr %program, i64 %index
  store i64 %packed, ptr %output.cell, align 8
  %next = add i64 %index, 1
  %prepared = icmp eq i64 %next, %count
  br i1 %prepared, label %empty.result, label %decode

dispatch:
  %pc = phi i64 [ 0, %mode ], [ %next.pc, %advance ]
  %acc = phi i32 [ 0, %mode ], [ %result, %advance ]
  %cell = getelementptr inbounds i64, ptr %program, i64 %pc
  %word = load i64, ptr %cell, align 8
  %offset32 = trunc i64 %word to i32
  %offset64 = sext i32 %offset32 to i64
  %target.bits = add i64 %offset64, ptrtoint (ptr @run to i64)
  %target = inttoptr i64 %target.bits to ptr
  %high = lshr i64 %word, 32
  %operand = trunc i64 %high to i32
  indirectbr ptr %target, [label %add, label %xor]

add:
  %sum = add i32 %acc, %operand
  br label %advance

xor:
  %mixed = xor i32 %acc, %operand
  br label %advance

advance:
  %result = phi i32 [ %sum, %add ], [ %mixed, %xor ]
  %next.pc = add i64 %pc, 1
  %finished = icmp eq i64 %next.pc, %count
  br i1 %finished, label %done, label %dispatch

done:
  %value = zext i32 %result to i64
  ret i64 %value

empty.result:
  ret i64 0

invalid:
  ret i64 -1
}

; Add 0x80000001, xor 0x80000000, add 42.
@source = private constant [3 x i64] [i64 -9223372032559808512, i64 -9223372036854775807, i64 180388626432]
@bad_opcode = private constant [1 x i64] [i64 2]

define i32 @main() {
  %program = alloca [3 x i64], align 8
  %bad = call i64 @run(ptr @bad_opcode, ptr %program, i64 1, i1 true)
  %rejected = icmp eq i64 %bad, -1
  %prepare = call i64 @run(ptr @source, ptr %program, i64 3, i1 true)
  %ready = icmp eq i64 %prepare, 0
  %first = call i64 @run(ptr null, ptr %program, i64 3, i1 false)
  %second = call i64 @run(ptr null, ptr %program, i64 3, i1 false)
  %first.correct = icmp eq i64 %first, 43
  %second.correct = icmp eq i64 %second, 43
  %valid.preparation = and i1 %rejected, %ready
  %valid.execution = and i1 %first.correct, %second.correct
  %correct = and i1 %valid.preparation, %valid.execution
  %status = select i1 %correct, i32 0, i32 1
  ret i32 %status
}
