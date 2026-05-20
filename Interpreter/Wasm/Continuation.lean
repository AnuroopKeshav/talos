import Interpreter.Wasm.Syntax
import Interpreter.Wasm.Locals

namespace Wasm

inductive Continuation where
| Fallthrough : Store → Locals → Continuation
| Break       : Nat → Store → Locals → Continuation
| Return      : Store → List Value → Continuation
/-- A trap aborts the current invocation. Per the wasm spec, side
effects already committed before the trap (memory writes, global
updates) are visible in the store carried here — only the in-flight
operand/locals state is lost. -/
| Trap        : Store → String → Continuation
| Invalid     : String → Continuation
| OutOfFuel   : Continuation
deriving Repr

inductive Result where
  | Success   : List Value → Store → Result
  /-- See `Continuation.Trap`: the store reflects every side effect
  committed before the trap was raised. -/
  | Trap      : Store → String → Result
  | Invalid   : String → Result
  | OutOfFuel : Result
deriving Repr

end Wasm
