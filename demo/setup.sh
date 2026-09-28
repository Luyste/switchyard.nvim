#!/usr/bin/env bash
# Builds a small demo repo (~/personal/projects/switchyard-demo, worktrees next
# to it) and starts pi agents in a tmux server of its own, so your own tmux
# sessions stay out of the videos.
# Safe to rerun: starts from scratch every time.
#
#   demo/setup.sh          repo + worktrees + agents
#   demo/setup.sh --clean  stop the demo agents and remove the demo repo
set -euo pipefail

REPO="$HOME/personal/projects/switchyard-demo"
export TMUX_TMPDIR=/tmp/switchyard-demo-tmux

tmux kill-server 2>/dev/null || true
rm -rf "$REPO" "$REPO".* "$TMUX_TMPDIR"
[ "${1:-}" = "--clean" ] && exit 0

mkdir -p "$TMUX_TMPDIR" "$REPO"
cd "$REPO"
git init -q -b main

cat >parser.py <<'PY'
"""Parse simple `key = value` config files."""


def parse_line(line):
    key, value = line.split("=", 1)
    return key.strip(), value.strip()


def parse(text):
    config = {}
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        key, value = parse_line(line)
        config[key] = value
    return config
PY

cat >app.py <<'PY'
from parser import parse


def main():
    with open("settings.conf") as f:
        settings = parse(f.read())
    theme = settings.get("theme", "light")
    print(f"Starting with the {theme} theme")


if __name__ == "__main__":
    main()
PY

cat >settings.conf <<'CONF'
# acme settings
theme = light
language = en
CONF

git add .
git -c user.name=demo -c user.email=demo@example.com commit -qm "a tiny config parser"

git worktree add -q -b feature/dark-mode "$REPO.feature-dark-mode"
git worktree add -q -b fix/parser-errors "$REPO.fix-parser-errors"

# One agent in main, one in the parser worktree. extended-keys lets pi tell
# Shift+Enter from Enter (it warns otherwise).
tmux new-session -d -s _setup \; set -s extended-keys on \; set -s extended-keys-format csi-u
tmux new-session -d -s pi-demo -c "$REPO" pi
tmux new-session -d -s pi-demo_fix-parser -c "$REPO.fix-parser-errors" pi
tmux kill-session -t =_setup

echo "demo ready in $REPO (tmux: TMUX_TMPDIR=$TMUX_TMPDIR)"
