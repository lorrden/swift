// REQUIRES: CPU=arm64, OS=macosx, executable_test
//
// RUN: %target-swift-frontend -disable-experimental-parser-round-trip -O -strict-memory-safety -warnings-as-errors -disable-availability-checking -emit-ir -disable-llvm-optzns %s | %FileCheck %s --implicit-check-not='define{{.*MachineV[0-9]+(advance|multiply|halt)}}'
// RUN: %target-build-swift -O -Xfrontend -disable-experimental-parser-round-trip -Xfrontend -strict-memory-safety -warnings-as-errors -Xfrontend -disable-availability-checking %s -o %t
// RUN: %target-run %t | %FileCheck %s --check-prefix=OUTPUT
// RUN: not --crash %target-run %t bounds

enum Opcode {
  case advance, multiply, halt
}

struct Machine {
  var value = 1
  var index = 0

  @_opcodeHandler(Opcode.advance)
  private mutating func advance() -> Int? {
    defer {
      index = 0
      value += 1
    }
    index += 1
    dispatch at index
  }

  @_opcodeHandler(Opcode.halt)
  private mutating func halt() -> Int? { nil }
}

extension Machine {
  @_opcodeHandler(Opcode.multiply)
  private mutating func multiply() -> Int? {
    value *= 2
    dispatch at 2
  }

  @_interpreterEntry
  mutating func run(_ program: Span<Opcode>, _ start: Int) -> Int {
    index = start
    dispatch at start
    return value
  }
}

// CHECK: @threaded.labels = private constant [3 x ptr]
// CHECK-LABEL: define{{.*}}MachineV3run
// CHECK: threaded.ready:
// CHECK: indirectbr ptr
// CHECK-NOT: call{{.*}}Machine
// CHECK: }

var machine = Machine()
if CommandLine.arguments.count > 1 {
  let invalid: [Opcode] = [.advance]
  print(machine.run(invalid.span, 0))
} else {
  let program: [Opcode] = [.advance, .multiply, .halt]
  print(machine.run(program.span, 0))
  var stopped = Machine()
  print(stopped.run(program.span, 2))
}

// OUTPUT: 4
// OUTPUT-NEXT: 1
