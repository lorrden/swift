; REQUIRES: CPU=arm64, OS=macosx, executable_test
;
; RUN: sed 's/^sil @run/sil [_semantics "experimental.direct_threading"] @run/' %S/threaded_dispatch_switch.sil > %t.sil
; RUN: %target-swift-frontend -parse-sil -module-name ThreadedDispatch -emit-ir -disable-llvm-optzns -Onone %t.sil -o %t.ll
; RUN: %FileCheck %s --check-prefix=IR < %t.ll
; RUN: %target-swift-frontend -parse-sil -module-name ThreadedDispatch -emit-ir -disable-llvm-optzns -O %t.sil -o %t.opt.ll
; RUN: %FileCheck %s --check-prefix=OPT < %t.opt.ll
; RUN: %clang-no-modules -target arm64-apple-macos13 -O2 -Wno-override-module -S -x ir %t.opt.ll -o - | %FileCheck %s --check-prefix=ASM
; RUN: %target-clang -O2 -Wno-override-module -x ir %t.opt.ll %s -o %t
; RUN: %target-run %t
; RUN: not --crash %target-run %t bad-opcode
; RUN: not --crash %target-run %t no-halt no-halt
;
; If a site's logical mapping differs, preserve both switches.
; RUN: sed 's/case %increment: bb9, case %double: bb10/case %increment: bb10, case %double: bb9/' %t.sil > %t.fallback.sil
; RUN: %target-swift-frontend -parse-sil -module-name ThreadedDispatch -emit-ir -disable-llvm-optzns -Onone %t.fallback.sil | %FileCheck %s --check-prefix=FALLBACK
;
; IR: @threaded.labels = private constant [4 x ptr] [ptr blockaddress(@run, %[[INC:[0-9]+]]), ptr blockaddress(@run, %[[DOUBLE:[0-9]+]]), ptr blockaddress(@run, %[[HALT:[0-9]+]]), ptr blockaddress(@run, %[[INVALID:[0-9]+]])]
; IR-LABEL: define{{.*}} @run(
; IR: %threaded.stream = alloca ptr, i64 3
; IR: threaded.prepare:
; IR: store ptr
; IR: threaded.ready:
; IR-NOT: switch i32
; IR: indirectbr ptr {{.*}}, [label %[[INC]], label %[[DOUBLE]], label %[[HALT]], label %[[INVALID]]]
; IR-NOT: switch i32
; IR: indirectbr ptr {{.*}}, [label %[[INC]], label %[[DOUBLE]], label %[[HALT]], label %[[INVALID]]]
; IR-NOT: switch i32
; IR: }
;
; Optimized SIL passes the PC and accumulator to handler block arguments.
; OPT: @threaded.labels = private constant
; OPT-LABEL: define{{.*}} @run(
; OPT-NOT: call{{.*}} @snapshot
; OPT: threaded.ready:
; OPT-NOT: load i32
; OPT: indirectbr
; OPT: phi i{{32|64}}
; OPT-NOT: load i32
; OPT: indirectbr
;
; ASM-LABEL: _run:
; ASM: Inner Loop Header
; ASM: ldr [[TARGET:x[0-9]+]], [
; ASM-NOT: {{[[:space:]](ldr|bl|blr)[[:space:]]}}
; ASM: br [[TARGET]]
; ASM: ret
;
; FALLBACK-NOT: @threaded.labels
; FALLBACK-LABEL: define{{.*}} @run(
; FALLBACK: switch i32
; FALLBACK: switch i32

@increment_then_double = private constant [3 x i32] [i32 0, i32 1, i32 2]
@double_then_increment = private constant [3 x i32] [i32 1, i32 0, i32 2]

declare swiftcc i32 @run(ptr)

@bad_opcode = private constant [3 x i32] [i32 0, i32 -1, i32 2]
@no_halt = private constant [3 x i32] [i32 0, i32 1, i32 0]

define i32 @main(i32 %argc, ptr %argv) {
entry:
  switch i32 %argc, label %out_of_range [i32 1, label %check_result
                                        i32 2, label %invalid_opcode]

invalid_opcode:
  %invalid_result = call swiftcc i32 @run(ptr @bad_opcode)
  ret i32 %invalid_result

out_of_range:
  %out_of_range_result = call swiftcc i32 @run(ptr @no_halt)
  ret i32 %out_of_range_result

check_result:
  %first = call swiftcc i32 @run(ptr @increment_then_double)
  %second = call swiftcc i32 @run(ptr @double_then_increment)
  %first.correct = icmp eq i32 %first, 4
  %second.correct = icmp eq i32 %second, 3
  %correct = and i1 %first.correct, %second.correct
  %status = select i1 %correct, i32 0, i32 1
  ret i32 %status
}
