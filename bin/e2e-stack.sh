#!/usr/bin/env bash
# e2e-stack.sh — Playwright tests of the member area against the local Supabase stack.
#
# The tests sign in as the seeded demo accounts and change data (a review, an
# appeal, a pledge, a new draft), so every run starts from a fresh
# `supabase db reset`: the seed is the fixture, and a second run sees the same
# world as the first.
#
# The publishable key is read from `supabase status` and exported as
# PUBLIC_SUPABASE_ANON_KEY for the build, exactly as bin/dev-run-web.sh does.
# It is never written to a file or echoed.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BACKEND="$REPO_ROOT/apps/backend"

if ! command -v supabase >/dev/null; then
  echo "==> The Supabase CLI isn't on PATH; see docs/STACK.md." >&2
  exit 1
fi

KEY=""
if KEY_LINE=$(cd "$BACKEND" && supabase status -o env 2>/dev/null | grep '^PUBLISHABLE_KEY='); then
  KEY=${KEY_LINE#PUBLISHABLE_KEY=}
  KEY=${KEY//\"/}
fi
if [ -z "$KEY" ]; then
  echo "==> The local stack isn't running. Start it with 'pnpm dev:db:up' first." >&2
  exit 1
fi

echo "==> Resetting the local database to seed.sql (the tests change data)."
(cd "$BACKEND" && supabase db reset)

echo "==> Local stack is up; key resolved (not printed)."
export PUBLIC_SUPABASE_ANON_KEY="$KEY"
exec pnpm -C "$REPO_ROOT/apps/web" exec playwright test -c playwright.stack.config.ts "$@"
