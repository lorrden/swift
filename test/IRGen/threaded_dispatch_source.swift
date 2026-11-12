// REQUIRES: CPU=arm64, OS=macosx, executable_test
//
// RUN: %target-swift-frontend -O -strict-memory-safety -warnings-as-errors -disable-availability-checking -emit-ir -disable-llvm-optzns %s | %FileCheck %s --check-prefix=IR
// RUN: %target-build-swift -O -Xfrontend -strict-memory-safety -warnings-as-errors -Xfrontend -disable-availability-checking %s -o %t
// RUN: %target-run %t | %FileCheck %s --check-prefix=OUTPUT
// RUN: not --crash %target-run %t bounds
// RUN: not --crash %target-run %t bounds bounds

enum Opcode {
  case increment, double, halt
}

@inline(never)
@_semantics("experimental.direct_threading")
func run(_ program: Span<Opcode>, _ start: Int) -> Int {
  var value = 1
  var pc = start
  if program.isEmpty { return value }
  while true {
    let opcode = program[pc]
    pc += 1
    switch opcode {
    case .increment: value += 1
    case .double: value *= 2
    case .halt: return value
    }
  }
}

// IR: @threaded.labels = private constant [3 x ptr]
// IR-LABEL: define{{.*}}run{{.*}}(ptr
// IR: threaded.prepare:
// IR: load i8
// IR: store ptr
// IR: threaded.ready:
// IR-NOT: load i8
// IR: indirectbr ptr
// IR: call{{.*}} @swift_slowDealloc

let first: [Opcode] = [.increment, .double, .halt]
let second: [Opcode] = [.double, .increment, .halt]
let empty: [Opcode] = []
if CommandLine.arguments.count > 1 {
  let pc = CommandLine.arguments.count == 2 ? -1 : first.count
  print(run(first.span, pc))
} else {
  print(run(first.span, 0))
  print(run(second.span, 0))
  print(run(empty.span, 0))
}

// OUTPUT: 4
// OUTPUT-NEXT: 3
// OUTPUT-NEXT: 1
