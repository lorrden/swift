// RUN: %target-swift-frontend -typecheck -verify -disable-availability-checking %s

public enum Opcode {
  case increment, halt
}

enum PayloadOpcode {
  case increment(Int), halt
}

@_interpreterEntry
func valid(_ program: Span<Opcode>) -> Int { program.count }

@_interpreterEntry // expected-error {{attribute cannot be applied to this declaration}}
func wrongBuffer(_ program: [Opcode]) {}

@_interpreterEntry // expected-error {{attribute cannot be applied to this declaration}}
func payload(_ program: Span<PayloadOpcode>) {}

@_interpreterEntry // expected-error {{attribute cannot be applied to this declaration}}
func asynchronous(_ program: Span<Opcode>) async {}

@_interpreterEntry // expected-error {{attribute cannot be applied to this declaration}}
func throwing(_ program: Span<Opcode>) throws {}

@_interpreterEntry // expected-error {{attribute cannot be applied to this declaration}}
func generic<T>(_ program: Span<Opcode>, _ value: T) {}

@_interpreterEntry // expected-error {{attribute cannot be applied to this declaration}}
public func publicEntry(_ program: Span<Opcode>) {}

@_interpreterEntry() // expected-error {{unexpected '(' in attribute '_interpreterEntry'}}
func takesNoAttributeArguments(_ program: Span<Opcode>) {}

@_interpreterEntry
@_interpreterEntry // expected-error {{duplicate attribute}}
func duplicate(_ program: Span<Opcode>) {}
