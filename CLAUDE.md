# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A project for **verifying WebAssembly code using Lean 4**. The vehicle is a built-in Wasm interpreter written in Lean: the same definitions that *execute* a program are the ones you *reason about*, so there is no separate "spec" interpreter to keep in sync with the runner.

The interpreter is deliberately optimized for **simplicity of reasoning, not execution speed**. When making changes, prefer the formulation that is easiest to unfold and `simp` through in proofs over the one that runs faster — performance work belongs behind a separate, proven-equivalent implementation, not in the reference interpreter.

Lean toolchain is pinned in `lean-toolchain`.

## Build / run / verify

```bash
lake build       # builds the libraries and the demo executable
lake exe wasminterpreterlean   # runs the example programs end-to-end
```

There is no separate test runner. Example correctness is encoded as Lean theorems and `native_decide` checks inside the examples; a successful `lake build` means every proof and decidable example check passed. To check a single source file in isolation: `lake env lean <path>`.

## Architecture

Three layers, deliberately small and currently i32-only:

- **Syntax (AST).** Instructions, functions, and modules. The instruction set today is a minimal i32 core (arithmetic, comparisons, locals, structured control flow `block`/`loop`/`br`/`brIf`/`iff`, `call`, `ret`, `drop`). No memory, globals, tables, imports, or non-i32 value types yet.
- **Semantics (interpreter).** A fuel-bounded big-step interpreter built around a single `step : Config → StepResult` function iterated by a `runLoop`. The execution state is a frame holding an operand stack (top-of-stack is the head of the list), a label stack for structured control flow, the remaining instructions, and locals; calls push the caller frame onto a call stack and return merges the callee's operand stack back onto it. Each label carries two continuations — one used on branch, one used on fall-through — which is how `block` vs `loop` differ. Insufficient operands, out-of-bounds access, division by zero, etc. produce a trap, which `run` surfaces as `none`.
- **Reasoning (examples).** Each example pairs a hand-built module with proofs. The standard proof style is: unfold the interpreter and `simp` to reduce both sides to the same concrete computation; concrete-input sanity checks use `native_decide`; larger results compose previously proven theorems as black boxes rather than re-unfolding the interpreter. New examples should follow this pattern.

## Public spec API: don't expose fuel

`run` takes an explicit `fuel : Nat` so that it terminates syntactically, but fuel is a proof obligation, not part of what a wasm function "does". User-facing specs should never mention fuel — no `∃ fuel, run … fuel = some rs` and no fixed numeric fuel in the statement. Use the fuel-free predicates from `WasmInterpreterLean/Spec/Termination.lean` instead:

- `Wasm.TerminatesWith m entry args P` — total correctness (some fuel succeeds, result satisfies `P`). Discharge via `TerminatesWith.of_run` / `of_run_eq` by exhibiting a concrete fuel internally.
- `Wasm.PartiallyMeets m entry args P` — partial correctness (every terminating fuel-bounded run satisfies `P`).

When writing or updating a `@[wasm_spec]` theorem, reach for these — the fuel value belongs inside the proof, not the statement.

## Examples: two layouts

Examples live in two places, with different roles:

- `Examples/Lean/` — small, hand-written Lean modules (e.g. `IsEven`, `IsOdd`, `SumTo`, `Factorial`, `Decoded`, `Spec/Bootstrap`). Each defines its `Wasm.Module` by hand and proves theorems against it. These are the simple, self-contained examples; they exercise the i32 interpreter directly and are imported from the top-level `WasmInterpreterLean.lean` library so they get built alongside the core.
- `Examples/programs/` — larger end-to-end examples driven by the `verifier` pipeline (Rust → wasm → WAT → Lean). Each one is its own Lake subproject with a `rust/` crate and a `lean/` project containing auto-generated `Program.lean` plus hand-written `Spec.lean` / `Proofs.lean`. Use this layout when the example is non-trivial enough to be worth writing in Rust, or when you want it surfaced in the `verifier ui` dashboard.

New work usually goes in `Examples/programs/`. Reach for `Examples/Lean/` only when you need a tight, hand-rolled module to exercise a specific interpreter feature.

## Planning notes

Active design notes for in-progress work live in `tasks/`. See `tasks/CLAUDE.md` for the ground rules — those files are human-curated and shouldn't be edited by agents without an explicit ask.
