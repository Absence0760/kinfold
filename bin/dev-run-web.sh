#!/usr/bin/env bash
# dev-run-web.sh — run apps/web against the local Supabase stack.
#
# The publishable key is read from `supabase status` and exported as
# PUBLIC_SUPABASE_ANON_KEY for Vite. It is never written to a file or echoed.
# The committed apps/web/.env.development carries only the non-sensitive URL.
#
# The marketing pages don't need the backend, so a stopped stack is a warning,
# not an error: the member area (/signin, /app) then shows a setup message.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BACKEND="$REPO_ROOT/apps/backend"

KEY=""
if command -v supabase >/dev/null && KEY_LINE=$(cd "$BACKEND" && supabase status -o env 2>/dev/null | grep '^PUBLISHABLE_KEY='); then
  KEY=${KEY_LINE#PUBLISHABLE_KEY=}
  KEY=${KEY//\"/}
fi

if [ -n "$KEY" ]; then
  echo "==> Local stack is up; key resolved (not printed)."
  echo "    Sign in at http://localhost:7790/signin with a demo account."
  export PUBLIC_SUPABASE_ANON_KEY="$KEY"
else
  echo "==> Local stack not running: marketing pages only."
  echo "    Run 'pnpm dev:db:up' first for the member area and demo sign-in."
fi

exec pnpm -C "$REPO_ROOT/apps/web" dev "$@"
