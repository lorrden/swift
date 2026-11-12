// REQUIRES: CPU=arm64, OS=macosx, executable_test
//
// RUN: %target-swift-frontend -disable-experimental-parser-round-trip -disable-availability-checking -emit-silgen %s | %FileCheck %s --check-prefix=SIL
// RUN: %target-swift-frontend -disable-experimental-parser-round-trip -O -strict-memory-safety -warnings-as-errors -disable-availability-checking -emit-ir -disable-llvm-optzns %s | %FileCheck %s --check-prefix=IR --implicit-check-not='define{{.*MachineV[0-9]+(increment|multiply|halt)}}'
// RUN: %target-build-swift -O -Xfrontend -disable-experimental-parser-round-trip -Xfrontend -strict-memory-safety -warnings-as-errors -Xfrontend -disable-availability-checking %s -o %t
// RUN: %target-run %t | %FileCheck %s --check-prefix=OUTPUT
// RUN: not --crash %target-run %t bounds
// RUN: not --crash %target-run %t bounds bounds

enum Opcode {
  case increment, double, halt
}

struct Machine {
  var value = 1
  var running = true

  @_opcodeHandler(Opcode.increment)
  private mutating func increment() {
    defer { value += 1 }
    value += 1
  }
}

extension Machine {
  @_opcodeHandler(Opcode.double)
  private mutating func multiply() { value *= 2 }

  @_opcodeHandler(Opcode.halt)
  private mutating func halt() { running = false }
}

extension Machine {
  @_interpreterEntry
  mutating func run(_ program: Span<Opcode>, _ start: Int) -> Int {
    var pc = start
    if program.isEmpty { return value }
    while running {
      let current = pc
      pc += 1
      dispatch at current
    }
    return value
  }
}

func execute(_ program: Span<Opcode>, _ pc: Int) -> Int {
  var machine = Machine()
  return machine.run(program, pc)
}

// SIL-DAG: sil private [always_inline]{{.*}} @{{.*}}9increment
// SIL-DAG: sil private [always_inline]{{.*}} @{{.*}}8multiply
// SIL-DAG: sil hidden [noinline] [_semantics "experimental.direct_threading"]{{.*}} @{{.*}}3run

// IR: @threaded.labels = private constant [3 x ptr]
// IR-LABEL: define{{.*}}run{{.*}}(ptr
// IR-NOT: call{{.*}}Machine
// IR: threaded.prepare:
// IR: load i8
// IR: store ptr
// IR: threaded.ready:
// IR-NOT: load i8
// IR: indirectbr ptr
// IR-NOT: call{{.*}}Machine
// IR: call{{.*}} @swift_slowDealloc
// IR-NOT: call{{.*}}Machine
// IR: }

let first: [Opcode] = [.increment, .double, .halt]
let second: [Opcode] = [.double, .increment, .halt]
let empty: [Opcode] = []
if CommandLine.arguments.count > 1 {
  let pc = CommandLine.arguments.count == 2 ? -1 : first.count
  print(execute(first.span, pc))
} else {
  print(execute(first.span, 0))
  print(execute(second.span, 0))
  print(execute(empty.span, 0))
}

// OUTPUT: 6
// OUTPUT-NEXT: 4
// OUTPUT-NEXT: 1
