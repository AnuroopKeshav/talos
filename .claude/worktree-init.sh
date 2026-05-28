#!/usr/bin/env bash
# Initialize a Claude Code worktree for fast Lean development.
#
# Detects when CWD is a worktree under <repo>/.claude/worktrees/<name>/, and
# seeds its Lake state by APFS-cloning .lake directories from the source repo.
# cp -c uses clonefile, so multi-GB .lake trees are copied in ~milliseconds and
# are copy-on-write — no extra disk usage until builds diverge.
#
# Idempotent: re-running is a near-instant no-op once .lake exists.

set -euo pipefail

cwd="$(pwd)"
case "$cwd" in
    */.claude/worktrees/*) ;;
    *) exit 0 ;;
esac

# Strip everything from /.claude/worktrees/... onward to find the source repo.
src="${cwd%/.claude/worktrees/*}"
if [[ ! -d "$src/.git" && ! -f "$src/.git" ]]; then
    echo "worktree-init: could not locate source repo (looked at $src)" >&2
    exit 0
fi

# Lake packages to seed. Add new package directories here if the repo grows.
pkgs=(interpreter codelib programs docbuild)

seeded=0
for pkg in "${pkgs[@]}"; do
    src_lake="$src/$pkg/.lake"
    dst_lake="$cwd/$pkg/.lake"
    [[ -d "$src_lake" ]] || continue
    [[ -d "$cwd/$pkg" ]] || continue
    [[ -e "$dst_lake" ]] && continue
    cp -c -R "$src_lake" "$dst_lake"
    seeded=$((seeded + 1))
done

if [[ $seeded -gt 0 ]]; then
    echo "worktree-init: cloned .lake into $seeded package(s) from $src"
fi

# Kick off a build so the worktree is warm and any drift from the source state
# (different commit, dirty files) is reconciled. Runs in background so the
# session starts immediately; output lands in .claude/worktree-init.log.
log="$cwd/.claude-worktree-init.log"
{
    echo "=== $(date) worktree-init build start ==="
    cd "$cwd"
    if command -v lake >/dev/null 2>&1; then
        lake -d "$cwd/programs" build || echo "lake build failed (exit $?)"
    else
        echo "lake not on PATH; skipping build"
    fi
    echo "=== $(date) worktree-init build end ==="
} >"$log" 2>&1 &
disown || true

echo "worktree-init: lake build running in background (tail $log)"
