#!/bin/sh
# builds build/site: the landing pages at the root and the flutter web app under /app/
set -eu
cd "$(dirname "$0")/.."
rm -rf build/site
flutter build web --release --no-wasm-dry-run --base-href /app/ -o "$PWD/build/site/app"
rsync -a --exclude build.sh --exclude serve.py site/ build/site/
echo "built build/site"
