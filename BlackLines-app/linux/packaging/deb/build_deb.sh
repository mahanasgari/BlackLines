#!/usr/bin/env bash
# Build the BlackLines .deb from a release Flutter bundle.
#
# Needs the Linux build deps (linux_deps.list), ImageMagick, dpkg-deb, and the
# desktop engine in hiddify-core/bin:  make linux-amd64-libs CHANNEL=prod
#
#   linux/packaging/deb/build_deb.sh [extra flutter build args]
#
# Output: dist/blacklines_<version>_amd64.deb
set -euo pipefail
cd "$(dirname "$0")/../../.."  # BlackLines-app/

FLUTTER=${FLUTTER:-flutter}
APP_ID=ir.cloudproducts.blacklines
NAME=blacklines
VERSION=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
ARCH=amd64
ICON=assets/images/source/blacklines_icon.png

if [ ! -f hiddify-core/bin/lib/hiddify-core.so ] || [ ! -f hiddify-core/bin/HiddifyCli ]; then
  echo "Desktop engine missing: run  make linux-amd64-libs CHANNEL=prod" >&2
  exit 1
fi

"$FLUTTER" build linux --release "$@"
BUNDLE=build/linux/x64/release/bundle

PKG=$(mktemp -d)
trap 'rm -rf "$PKG"' EXIT
install -d "$PKG/DEBIAN" "$PKG/opt/$NAME" "$PKG/usr/bin" "$PKG/usr/share/applications"
cp -a "$BUNDLE/." "$PKG/opt/$NAME/"
ln -s "/opt/$NAME/$NAME" "$PKG/usr/bin/$NAME"

for size in 48 64 128 256 512; do
  dir="$PKG/usr/share/icons/hicolor/${size}x${size}/apps"
  install -d "$dir"
  convert "$ICON" -resize "${size}x${size}" "$dir/$APP_ID.png"
done

# The file name and StartupWMClass match the GTK application id, so GNOME
# shows this icon in the dock and app grid.
cat >"$PKG/usr/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=BlackLines
GenericName=VPN
Comment=Buy, manage and connect to your BlackLines VPN
Exec=/opt/$NAME/$NAME %U
Icon=$APP_ID
Terminal=false
Categories=Network;
Keywords=VPN;Proxy;BlackLines;
StartupNotify=true
StartupWMClass=$APP_ID
EOF

cat >"$PKG/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: BlackLines <noreply@cloudproducts.ir>
Installed-Size: $(du -sk "$PKG" | cut -f1)
Depends: libgtk-3-0t64 | libgtk-3-0, libsecret-1-0, libayatana-appindicator3-1
Section: net
Priority: optional
Homepage: https://t.me/blacklinessbot
Description: BlackLines VPN client
 Buy, manage and connect to BlackLines VPN configs.
 Connection engine: Hiddify / sing-box (GPLv3).
EOF

cat >"$PKG/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
EOF
cp "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"
chmod 0755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

mkdir -p dist
OUT="dist/${NAME}_${VERSION}_${ARCH}.deb"
fakeroot dpkg-deb --build --root-owner-group "$PKG" "$OUT"
echo "Built $OUT"
