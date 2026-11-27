#!/bin/bash
set -euo pipefail

DEST="${HOME}/.local/bin"
mkdir -p "$DEST"

cp bin/panelgraph-daemon "$DEST/"
cp bin/panelgraph-show "$DEST/"
cp bin/panelgraph-popup "$DEST/"
chmod +x "$DEST/panelgraph-daemon" "$DEST/panelgraph-show" "$DEST/panelgraph-popup"

echo "Installed to $DEST/"
echo ""
echo "Next: add a Generic Monitor panel item with command:"
echo "  $DEST/panelgraph-show net"
