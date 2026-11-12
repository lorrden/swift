// RUN: %target-swift-frontend -disable-experimental-parser-round-trip -typecheck -verify -disable-availability-checking %s

enum Opcode {
  case step, halt
}

struct MissingHandler {
  @_opcodeHandler(Opcode.step)
  mutating func step() {}

  @_interpreterEntry
  mutating func run(_ program: Span<Opcode>) {
    dispatch at 0 // expected-error {{missing opcode handler for 'halt'}}
  }
}

struct DuplicateHandler {
  @_opcodeHandler(Opcode.step)
  mutating func step() {}

  @_opcodeHandler(Opcode.step) // expected-error {{duplicate opcode handler}}
  mutating func otherStep() {}

  @_opcodeHandler(Opcode.halt)
  mutating func halt() {}

  @_interpreterEntry
  mutating func run(_ program: Span<Opcode>) {
    dispatch at 0
  }
}

struct InvalidBinding {
  @_opcodeHandler(Opcode.unknown) // expected-error {{attribute cannot be applied to this declaration}}
  mutating func unknown() {}
}

func outsideEntry() {
  dispatch at 0 // expected-error {{'dispatch at' requires a mutating @_interpreterEntry method}}
}

struct NestedDispatch {
  @_opcodeHandler(Opcode.step)
  mutating func step() {}

  @_opcodeHandler(Opcode.halt)
  mutating func halt() {}

  @_interpreterEntry
  mutating func run(_ program: Span<Opcode>) {
    let closure: () -> Void = {
      dispatch at 0 // expected-error {{'dispatch at' requires a mutating @_interpreterEntry method}}
    }
    closure()
  }
}

struct MixedResults {
  @_opcodeHandler(Opcode.step)
  mutating func step() -> Int? { nil }

  @_opcodeHandler(Opcode.halt)
  mutating func halt() {}

  @_interpreterEntry
  mutating func run(_ program: Span<Opcode>) {
    dispatch at 0 // expected-error {{opcode handlers must all return Void or all return Int?}}
  }
}

struct VoidTransfer {
  @_opcodeHandler(Opcode.step)
  mutating func step() {
    dispatch at 0 // expected-error {{'dispatch at' in a handler requires an Int? result}}
  }
}

struct OptionalTransfer {
  @_opcodeHandler(Opcode.step)
  mutating func step() -> Int? {
    dispatch at nil // expected-error {{'nil' cannot be used in context expecting type 'Int'}}
  }
}
