programs_dir := justfile_directory() / "Examples/programs"

# Run the WebAssembly spec testsuite (vendor/testsuite/). Optional pattern
# is a case-sensitive substring on the .wast filename stem.
testsuite pattern="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{pattern}}" ]]; then
        lake exe testsuite "{{pattern}}"
    else
        lake exe testsuite
    fi

# List all example programs
list:
    @ls {{programs_dir}}

# Build the Lean proofs for one program (or all if name omitted)
build name="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{name}}" ]]; then
        targets=("{{name}}")
    else
        targets=($(ls "{{programs_dir}}"))
    fi
    for p in "${targets[@]}"; do
        echo "==> build $p"
        (cd "{{programs_dir}}/$p/lean" && lake build)
    done

# Run `lake exe verifier check` for one program (or all if name omitted)
check name="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{name}}" ]]; then
        targets=("{{name}}")
    else
        targets=($(ls "{{programs_dir}}"))
    fi
    for p in "${targets[@]}"; do
        echo "==> check $p"
        (cd "{{programs_dir}}/$p/lean" && lake exe verifier check)
    done

# Build the UI for one program (or all if name omitted)
ui name="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{name}}" ]]; then
        targets=("{{name}}")
    else
        targets=($(ls "{{programs_dir}}"))
    fi
    for p in "${targets[@]}"; do
        echo "==> ui $p"
        (cd "{{programs_dir}}/$p/lean" && lake exe verifier build && lake exe verifier ui)
    done

# Build + check (default: all programs, useful for CI)
verify name="": (build name) (check name)

# Smoke-test `./.lake/build/bin/runner` against samples/.
runner-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    lake build runner

    fail=0

    check() {
        local name="$1"; shift
        local want_exit="$1"; shift
        local want_stream="$1"; shift  # "stdout" or "stderr"
        local want="$1"; shift
        local got got_exit
        if [[ "$want_stream" == stdout ]]; then
            got=$(./.lake/build/bin/runner "$@" 2>/dev/null) && got_exit=0 || got_exit=$?
        else
            got=$(./.lake/build/bin/runner "$@" 2>&1 >/dev/null) && got_exit=0 || got_exit=$?
        fi
        if [[ "$got_exit" != "$want_exit" || "$got" != "$want" ]]; then
            echo "FAIL: $name"
            echo "  cmd:    ./.lake/build/bin/runner $*"
            echo "  expect: exit=$want_exit $want_stream=[$want]"
            echo "  got:    exit=$got_exit $want_stream=[$got]"
            fail=1
        else
            echo "ok: $name"
        fi
    }

    check "sum_to.wat"        0 stdout "55"                          samples/sum_to.wat sum_to 10
    check "factorial.wat"     0 stdout "120"                         samples/factorial.wat fact 5
    check "trap.wat"          1 stderr "trap: integer divide by zero" samples/trap.wat div_by_zero
    check "out-of-fuel"       2 stderr "out of fuel"                  samples/sum_to.wat sum_to 1000000 --fuel 10

    if command -v wasm-tools >/dev/null 2>&1; then
        tmpdir=$(mktemp -d -t runner-smoke.XXXXXX)
        trap 'rm -rf "$tmpdir"' EXIT
        tmp="$tmpdir/sum_to.wasm"
        wasm-tools parse samples/sum_to.wat -o "$tmp"
        check "sum_to.wasm via wasm-tools" 0 stdout "55" "$tmp" sum_to 10
    else
        echo "skip: wasm-tools not on PATH; .wasm round-trip not exercised"
    fi

    exit $fail
