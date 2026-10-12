#!/bin/bash
# Installs MacSleep.app into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

echo "▸ Installation dans /Applications…"
rm -rf "/Applications/MacSleep.app"
cp -R dist/MacSleep.app "/Applications/MacSleep.app"

echo "✓ Installé. Ouvrez-le depuis le Launchpad ou :"
echo "  open /Applications/MacSleep.app"
