; REQUIRES: CPU=arm64, OS=macosx, executable_test
;
; RUN: sed -e 's/^sil @run/sil [_semantics "experimental.direct_threading"] @run/' -e 's/(Builtin.RawPointer) -> Builtin.Int32/(Builtin.RawPointer, Builtin.Word) -> Builtin.Int32/' -e 's/^bb0(%code : \$Builtin.RawPointer):/bb0(%code : $Builtin.RawPointer, %length : $Builtin.Word):/' -e '/^  %length = integer_literal/d' %S/threaded_dispatch_switch.sil > %t.sil
; RUN: %target-swift-frontend -parse-sil -module-name ThreadedDispatch -emit-ir -disable-llvm-optzns -O %t.sil -o %t.ll
; RUN: %FileCheck %s < %t.ll
; RUN: %target-clang -O2 -Wno-override-module -x ir %t.ll %s -L %swift-lib-dir/swift/macosx -lswiftCore -o %t
; RUN: %target-run %t
; RUN: not --crash %target-run %t empty
; RUN: not --crash %target-run %t oversized oversized
;
; Prepare 65,536 addresses, then execute the entire stream. A second call
; with a shorter stream checks that the buffer and its bounds are per call.
;
; CHECK-LABEL: define{{.*}} @run(
; CHECK-SAME: ptr {{[^,]+}}, i64 [[COUNT:%[0-9]+]])
; CHECK: icmp eq i64 [[COUNT]], 0
; CHECK: icmp ugt i64 [[COUNT]], 1152921504606846975
; CHECK: [[SIZE:%[0-9]+]] = mul i64 [[COUNT]], 8
; CHECK: [[STREAM:%[-a-zA-Z0-9.]+]] = call{{.*}} @swift_slowAlloc(i64 [[SIZE]], i64 7)
; CHECK: threaded.prepare:
; CHECK: store ptr
; CHECK: threaded.ready:
; CHECK: indirectbr
; CHECK: indirectbr
; CHECK: call{{.*}} @swift_slowDealloc(ptr [[STREAM]], i64 [[SIZE]], i64 7)
; CHECK: ret i32

@large = private global [65536 x i32] zeroinitializer
@small = private constant [3 x i32] [i32 1, i32 0, i32 2]

declare swiftcc i32 @run(ptr, i64)

define i32 @main(i32 %argc, ptr %argv) {
entry:
  switch i32 %argc, label %oversized [i32 1, label %execute
                                     i32 2, label %empty]

execute:
  %halt = getelementptr [65536 x i32], ptr @large, i64 0, i64 65535
  store i32 2, ptr %halt
  %first = call swiftcc i32 @run(ptr @large, i64 65536)
  %second = call swiftcc i32 @run(ptr @small, i64 3)
  %first.correct = icmp eq i32 %first, 65536
  %second.correct = icmp eq i32 %second, 3
  %correct = and i1 %first.correct, %second.correct
  %status = select i1 %correct, i32 0, i32 1
  ret i32 %status

empty:
  %empty.result = call swiftcc i32 @run(ptr @small, i64 0)
  ret i32 %empty.result

oversized:
  %oversized.result = call swiftcc i32 @run(ptr @small, i64 1152921504606846976)
  ret i32 %oversized.result
}
