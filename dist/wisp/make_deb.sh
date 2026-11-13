#!/usr/bin/env bash
# Assembles a binary .deb from a staging tree produced by `zig build install`.
#
# Usage: make_deb.sh VERSION STAGING OUT
#   VERSION  Debian version string, e.g. 1.4.0+wisp.1
#   STAGING  Directory whose usr/ subtree will become the .deb payload
#   OUT      Output .deb filename
set -euo pipefail

VERSION="$1"
STAGING="$2"
OUT="$3"

mkdir -p "$STAGING/DEBIAN"

cat > "$STAGING/DEBIAN/control" <<EOF
Package: wisp
Version: $VERSION
Architecture: amd64
Maintainer: Callisto Bound
Homepage: https://github.com/${GITHUB_REPOSITORY:-callistobound/wisp}
Section: x11
Priority: optional
Depends: libgtk-4-1, libadwaita-1-0, libgstreamer1.0-0,
 gstreamer1.0-plugins-base, libxkbcommon0
Description: Wisp terminal emulator
 Wisp is a fork of Ghostty, a fast, feature-rich, and cross-platform
 terminal emulator.
EOF

cat > "$STAGING/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-icon-caches >/dev/null 2>&1; then
    update-icon-caches /usr/share/icons/hicolor
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications
fi
EOF
chmod 0755 "$STAGING/DEBIAN/postinst"

dpkg-deb --build --root-owner-group "$STAGING" "$OUT"
echo "Built: $OUT ($(du -sh "$OUT" | cut -f1))"
