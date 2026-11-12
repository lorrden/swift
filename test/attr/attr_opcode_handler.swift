// RUN: split-file %s %t
// RUN: %target-swift-frontend -typecheck -verify %t/machine.swift %t/extension.swift

//--- machine.swift
struct Machine {
  var value = 0

  @_opcodeHandler
  mutating func increment() { value += 1 }

  @_opcodeHandler // expected-error {{attribute cannot be applied to this declaration}}
  func nonmutating() {}

  @_opcodeHandler // expected-error {{attribute cannot be applied to this declaration}}
  mutating func withArgument(_ value: Int) {}

  @_opcodeHandler // expected-error {{attribute cannot be applied to this declaration}}
  mutating func withResult() -> Int { value }

  @_opcodeHandler // expected-error {{attribute cannot be applied to this declaration}}
  @inline(never)
  mutating func refusesInlining() {}

  @_opcodeHandler // expected-error {{attribute cannot be applied to this declaration}}
  mutating func asynchronous() async {}
}

extension Machine {
  @_opcodeHandler
  mutating func double() { value *= 2 }
}

@_opcodeHandler // expected-error {{attribute cannot be applied to this declaration}}
func freeFunction() {}

//--- extension.swift
extension Machine {
  @_opcodeHandler // expected-error {{attribute cannot be applied to this declaration}}
  mutating func elsewhere() {}
}
