# WasmInterpreterLean

A WebAssembly interpreter written in Lean 4, built so that the same definitions you execute are the ones you reason about.

The goal is to have an executable semantics for Wasm that doubles as a formal object: you can run programs on concrete inputs, and you can state and prove theorems about their behavior — correctness against a spec, equivalence between programs, properties that hold for all inputs — using Lean's proof tooling.

## Structure

The project is organized around three layers:

- **Syntax** — the abstract representation of Wasm programs.
- **Semantics** — a pure, executable interpreter that gives meaning to that syntax.
- **Reasoning** — example programs together with proofs about how the interpreter behaves on them.

Because the interpreter is an ordinary Lean function, evaluation and proof use the exact same definitions; there is no separate "spec" interpreter to keep in sync.

## Dependencies

- **Lean 4** — toolchain pinned in `lean-toolchain`, fetched automatically by `elan`.
- **[`wasm-tools`](https://github.com/bytecodealliance/wasm-tools)** — used to convert real `.wasm` binaries into the WAT text format that the Lean-side decoder (`WasmInterpreterLean.Decoder.Wat`) consumes. Install with `brew install wasm-tools` (macOS) or `cargo install wasm-tools`. Only needed when decoding external modules; the existing examples and proofs build without it.

## Running modules with `runner`

`runner` is the CLI front-end: it loads a `.wat` or `.wasm` module, invokes one of its functions on the supplied arguments, and prints the results.

```
lake exe runner [--fuel N] [-h|--help] <file> <method> [args...]
```

- **`<file>`**: path ending in `.wat` (read directly) or `.wasm` (decoded via `wasm-tools print`; requires `wasm-tools` on `PATH`).
- **`<method>`**: an export name (e.g. `sum_to`), or a non-negative integer interpreted as a function index. The integer rule always wins — an export literally named `"0"` is unreachable here.
- **`[args...]`**: one numeric literal per declared parameter. Decimal (`42`, `-1`) and hex (`0xff`) accepted. The declared parameter type drives the width/signedness coercion (no typed prefixes like `i32:`).
- **`--fuel N`**: reduction-step cap, default `1_000_000`.

**Output**: one result per line on stdout, bare signed decimal. Exit codes: `0` success, `1` trap (stderr `trap: <reason>`), `2` out of fuel (stderr `out of fuel`), `3` decode / CLI / setup error (stderr `error: <msg>`).

A few ready-to-run modules live in [`samples/`](samples):

```
$ lake exe runner samples/sum_to.wat sum_to 10
55

$ lake exe runner samples/factorial.wat fact 5
120

$ lake exe runner samples/trap.wat div_by_zero
trap: integer divide by zero        # on stderr, exit 1

$ lake exe runner samples/sum_to.wat sum_to 1000000 --fuel 10
out of fuel                          # on stderr, exit 2
```

To run on a `.wasm` you have on disk, point `runner` straight at it — e.g. `lake exe runner build/foo.wasm my_export 42`. To turn one of the `.wat` samples into a `.wasm`, use `wasm-tools parse samples/sum_to.wat -o sum_to.wasm`.

The recipe `just runner-smoke` exercises all of the above end-to-end.

## Verifying Rust code with `verifier`

`verifier` automates the rust → wasm → wat → Lean pipeline so you can attach a Lean-level specification and proofs to a Rust crate. It expects `cargo`, the `wasm32-unknown-unknown` target, and `wasm-tools` on `PATH`.

```
lake exe verifier new <rust-project> [--out <dir>] [--name <Name>] [--wasm-interpreter <path>]
lake exe verifier build       # run from inside the generated project
lake exe verifier check       # CI-friendly: assert Program.lean is up to date, then `lake build`
lake exe verifier ui          # generate a static site under build/site/
```

`new` reads the crate name from the Rust project's `Cargo.toml`, derives a Lean module prefix (`my_thing` → `MyThing`), and writes a Lake project with `verifier.toml`, `lakefile.toml`, `lean-toolchain` (copied from this repo), a root `<Name>.lean`, and stub `<Name>/Spec.lean` and `<Name>/Proofs.lean` for you to fill in. The path to `WasmInterpreterLean` is auto-detected from the running binary; pass `--wasm-interpreter` to override.

`build` compiles the Rust crate to wasm, regenerates `Program.lean` from the resulting module, and builds the Lean project.

`check` is the CI counterpart: it regenerates `Program.lean` in-memory, fails if the committed file is stale, and otherwise builds the Lean project.

`ui` consumes `build/specs.json` and `build/<crate>.wat` (so run `build` first) and writes a static site to `build/site/` summarising the `@[wasm_spec]` surface, exports, and source trees.

A worked example lives at [`Examples/programs/factorial`](Examples/programs/factorial).
