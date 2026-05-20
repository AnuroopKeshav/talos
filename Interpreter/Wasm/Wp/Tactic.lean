import Interpreter.Wasm.Wp.Atomic

/-! ### Tactics.

    `wp_run` symbolically executes straight-line code by reducing the atomic
    `wp_*_cons` equations. It stops at control-flow boundaries (`block`,
    `loop`, `iff`, `call`), where the user supplies invariants / specs
    explicitly. -/

namespace Wasm

macro "wp_run" : tactic => `(tactic|
  simp only [wp_simp,
    -- Helpers
    Locals.get, Locals.set?, Locals.validIndex,
    Function.toLocals, Function.numParams, Function.numLocals,
    List.take, List.drop, List.replicate, List.length, List.map,
    ValueType.zero, List.headD])

macro "wp_done" : tactic => `(tactic| (wp_run; first | rfl | grind))

end Wasm
