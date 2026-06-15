#!/usr/bin/env bash
set -euo pipefail

# One-command redeploy for Explorife (Flutter web -> Vercel).
# Builds a release bundle and pushes build/web to the explorife2 production domain.

FLUTTER="/Users/toan/development/flutter/bin/flutter"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_BACKUP="$ROOT/.vercel-link"

cd "$ROOT"

# Preserve the Vercel project link, since `flutter build web` can wipe build/web.
if [ -d "build/web/.vercel" ]; then
  rm -rf "$LINK_BACKUP"
  cp -r "build/web/.vercel" "$LINK_BACKUP"
fi

echo "==> Building Flutter web (release)..."
"$FLUTTER" build web --release

# Restore the link so the deploy is non-interactive.
if [ -d "$LINK_BACKUP" ]; then
  cp -r "$LINK_BACKUP" "build/web/.vercel"
fi

echo "==> Deploying build/web to Vercel production..."
cd "$ROOT/build/web"
npx vercel deploy --prod --yes

echo "==> Done. Verifying production..."
curl -sI https://explorife2.vercel.app/ | grep -iE "http/|x-vercel-error" || true
