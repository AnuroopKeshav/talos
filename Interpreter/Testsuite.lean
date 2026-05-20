import Interpreter.Testsuite.Exec

/-!
# `testsuite` — run the W3C Wasm spec testsuite against this interpreter

  lake exe testsuite [--fuel N] [-h|--help] [PATTERN]

If `PATTERN` is omitted, runs every top-level `.wast` file under
`vendor/testsuite/`. Otherwise filters to files whose relative path
contains `PATTERN` as a substring (case-sensitive). Subdirectories of
`vendor/testsuite/` (e.g. `proposals/`, `legacy/`) are not recursed.

Per `.wast` file we shell out to `wasm-tools json-from-wast` to split the
script into a JSON manifest plus per-module `.wasm` files, then walk the
commands. Only `module`, `assert_return`, `assert_trap`, and `action` are
executed — every other command type (`assert_invalid`, `assert_malformed`,
`register`, `assert_unlinkable`, etc.) is reported as `Skipped(<kind>)`.

Exit code: nonzero iff any `Fail`, `InterpreterError`, or `OutOfFuel`
outcome was recorded. `DecodeError`/`ModuleUnavailable`/`Skipped` don't
fail the run — they're "feature not implemented" signal, not regressions.
-/

namespace Wasm.Testsuite

/-! ## Setup -/

def defaultFuel : Nat := 1_000_000

def testsuiteDir : String := "vendor/testsuite"

def usage : String :=
"Usage: lake exe testsuite [--fuel N] [-h|--help] [PATTERN]

  PATTERN     If given, only run .wast files whose path contains this substring.
              If omitted, run every top-level .wast file under vendor/testsuite/.
  --fuel N    Per-assertion reduction-step cap, default 1_000_000.
  -h, --help  Print this message and exit 0."

structure Args where
  pattern : Option String
  fuel    : Nat

partial def splitFlags
    (toks : List String) (acc : List String) (fuel : Nat) (help : Bool)
    : Except String (List String × Nat × Bool) :=
  match toks with
  | [] => .ok (acc.reverse, fuel, help)
  | "-h" :: rest | "--help" :: rest =>
    splitFlags rest acc fuel true
  | "--fuel" :: nStr :: rest =>
    match nStr.toNat? with
    | some n => splitFlags rest acc n help
    | none   => .error s!"--fuel expects a non-negative integer, got `{nStr}`"
  | "--fuel" :: [] => .error "--fuel expects an argument"
  | tok :: rest => splitFlags rest (tok :: acc) fuel help

def parseArgs (argv : List String) : Except String (Sum Unit Args) := do
  let (pos, fuel, help) ← splitFlags argv [] defaultFuel false
  if help then return .inl ()
  match pos with
  | [] => return .inr { pattern := none, fuel }
  | [p] => return .inr { pattern := some p, fuel }
  | _ => .error "expected at most one PATTERN argument"

/-! ## File discovery -/

/-- Top-level `.wast` files in `vendor/testsuite/`, sorted, optionally
filtered by substring. Errors propagate as `IO` exceptions. -/
def discoverFiles (pattern? : Option String) : IO (Array String) := do
  let entries ← (System.FilePath.mk testsuiteDir).readDir
  let mut out : Array String := #[]
  for e in entries do
    let name := e.fileName
    if name.endsWith ".wast" then
      let keep : Bool := match pattern? with
        | some p => decide ((name.splitOn p).length > 1)
        | none   => true
      if keep then
        out := out.push s!"{testsuiteDir}/{name}"
  return out.qsort (· < ·)

/-! ## Counters and formatting -/

structure Counts where
  pass             : Nat := 0
  fail             : Nat := 0
  skipped          : Nat := 0
  decodeError      : Nat := 0
  interpreterError : Nat := 0
  outOfFuel        : Nat := 0
  cascade          : Nat := 0
deriving Inhabited

def Counts.add (a b : Counts) : Counts := {
  pass := a.pass + b.pass,
  fail := a.fail + b.fail,
  skipped := a.skipped + b.skipped,
  decodeError := a.decodeError + b.decodeError,
  interpreterError := a.interpreterError + b.interpreterError,
  outOfFuel := a.outOfFuel + b.outOfFuel,
  cascade := a.cascade + b.cascade,
}

instance : Add Counts := ⟨Counts.add⟩

def tallyOne (c : Counts) : Outcome → Counts
  | .pass               => { c with pass := c.pass + 1 }
  | .fail _             => { c with fail := c.fail + 1 }
  | .skipped _          => { c with skipped := c.skipped + 1 }
  | .decodeError _      => { c with decodeError := c.decodeError + 1 }
  | .interpreterError _ => { c with interpreterError := c.interpreterError + 1 }
  | .outOfFuel          => { c with outOfFuel := c.outOfFuel + 1 }
  | .moduleUnavailable  => { c with cascade := c.cascade + 1 }

def tally (rs : Array CmdResult) : Counts :=
  rs.foldl (fun c r => tallyOne c r.outcome) {}

/-- True if this file's overall outcome should bump the exit code. -/
def Counts.hasFailure (c : Counts) : Bool :=
  c.fail > 0 || c.interpreterError > 0 || c.outOfFuel > 0

/-- Pad a string on the right to `width` columns. -/
def padR (s : String) (width : Nat) : String :=
  let n := s.length
  if n >= width then s else s ++ "".pushn ' ' (width - n)

private def basename (path : String) : String :=
  (System.FilePath.mk path).fileName.getD path

/-- Short one-line summary of the outcome, for failure detail lines. -/
def outcomeSummary : Outcome → String
  | .pass               => "Pass"
  | .fail msg           => s!"Fail  {msg}"
  | .skipped r          => s!"Skipped({r})"
  | .decodeError m      => s!"DecodeError  {m}"
  | .interpreterError m => s!"InterpreterError  {m}"
  | .outOfFuel          => "OutOfFuel"
  | .moduleUnavailable  => "ModuleUnavailable"

/-- Build the per-file report. Renders one summary row, plus zero or more
detail lines: one per failed `module`/`assert_*`/`action`, with cascade
runs collapsed by suppressing `ModuleUnavailable` lines (their count is
in the summary). -/
def renderFile (fr : FileResult) : String := Id.run do
  let mut buf : String := ""
  let c := tally fr.results
  let name := basename fr.path
  -- Summary row.
  let row := s!"{padR name 32}  {padR (toString c.pass) 4} pass  {padR (toString c.fail) 4} fail  {padR (toString c.skipped) 4} skip"
  let row := if c.cascade > 0 then s!"{row}  {padR (toString c.cascade) 4} cascade" else row
  let row := if c.decodeError > 0 then s!"{row}  {c.decodeError} decode-err" else row
  let row := if c.interpreterError > 0 then s!"{row}  {c.interpreterError} interp-err" else row
  let row := if c.outOfFuel > 0 then s!"{row}  {c.outOfFuel} out-of-fuel" else row
  buf := buf ++ row ++ "\n"
  match fr.fileError with
  | some e => buf := buf ++ s!"  ERROR  {e}\n"; return buf
  | none => pure ()
  -- Detail lines for everything except pass / moduleUnavailable / skipped.
  for r in fr.results do
    match r.outcome with
    | .pass | .moduleUnavailable | .skipped _ => pure ()
    | _ =>
      buf := buf ++ s!"  L{r.line}  {padR r.kind 14}  {outcomeSummary r.outcome}\n"
  return buf

/-! ## Main loop -/

def EXIT_OK   : UInt32 := 0
def EXIT_FAIL : UInt32 := 1
def EXIT_ERR  : UInt32 := 3

/-- Make a process-scoped temp dir via `mktemp -d`. Returns `.error` if
neither `mktemp` is on PATH nor a sensible fallback exists. -/
def makeTempDir : IO (Except String String) := do
  let res ← (IO.Process.output { cmd := "mktemp", args := #["-d", "-t", "wasm-testsuite.XXXXXXXX"] }).toBaseIO
  match res with
  | .ok out =>
    if out.exitCode = 0 then return .ok out.stdout.trimAscii.toString
    else return .error s!"mktemp failed: {out.stderr.trimAscii.toString}"
  | .error _ =>
    return .error "could not create a temporary directory (mktemp not found)"

def runAll (a : Args) : IO UInt32 := do
  let files ← try discoverFiles a.pattern
    catch e =>
      IO.eprintln s!"error: could not read {testsuiteDir}: {e.toString}"
      return EXIT_ERR
  if files.isEmpty then
    let msg := match a.pattern with
      | some p => s!"no .wast files matched `{p}` in {testsuiteDir}"
      | none   => s!"no .wast files in {testsuiteDir}"
    IO.eprintln msg
    return EXIT_ERR

  let tmpRoot ← match (← makeTempDir) with
    | .ok d    => pure d
    | .error e => IO.eprintln s!"error: {e}"; return EXIT_ERR

  let mut totals : Counts := {}
  let mut anyFailure := false

  try
    for path in files do
      let fr ← Wasm.Testsuite.runFile path tmpRoot a.fuel
      IO.print (renderFile fr)
      let c := tally fr.results
      totals := totals + c
      if c.hasFailure then anyFailure := true
  finally
    -- Best-effort cleanup; if it fails, the OS will reap eventually.
    try IO.FS.removeDirAll tmpRoot catch _ => pure ()

  IO.println ""
  IO.println s!"Totals: {totals.pass} pass  {totals.fail} fail  {totals.skipped} skip  {totals.cascade} cascade  {totals.decodeError} decode-err  {totals.interpreterError} interp-err  {totals.outOfFuel} out-of-fuel"

  return if anyFailure then EXIT_FAIL else EXIT_OK

end Wasm.Testsuite

open Wasm.Testsuite in
def main (argv : List String) : IO UInt32 := do
  match parseArgs argv with
  | .error msg =>
    IO.eprintln s!"error: {msg}"
    IO.eprintln usage
    return EXIT_ERR
  | .ok (.inl ()) =>
    IO.println usage
    return EXIT_OK
  | .ok (.inr a) => runAll a
