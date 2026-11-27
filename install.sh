#!/bin/bash
set -euo pipefail

DEST="${HOME}/.local/bin"
mkdir -p "$DEST"

cp bin/panelgraph-daemon "$DEST/"
cp bin/panelgraph-show "$DEST/"
chmod +x "$DEST/panelgraph-daemon" "$DEST/panelgraph-show"

echo "Installed to $DEST/"
echo ""
echo "Next: add a Generic Monitor panel item with command:"
echo "  $DEST/panelgraph-show net"
