#!/usr/bin/env bash
# Builds the macOS release and packages it as a .dmg:
#   build/dist/returner-<version>-macos.dmg
#
# Run on macOS, from the repository root. Needs Xcode, Flutter, Go and git.
#
#   tool/package_macos.sh                 # unsigned, for yourself
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" tool/package_macos.sh
#
# Not verified on a Mac since the helper tools moved to Contents/MacOS.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script packages the macOS build and must run on macOS." >&2
  exit 1
fi

version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)"
if [[ -z "$version" ]]; then
  echo "No version in pubspec.yaml." >&2
  exit 1
fi

dist="build/dist"
universal="build/dist/macos-bin"
app="build/macos/Build/Products/Release/returner.app"
dmg="$dist/returner-$version-macos.dmg"
mkdir -p "$universal"

# ipatool uses the system keychain through cgo, so each architecture is built
# natively by the Go toolchain on this Mac and the two are merged.
echo "Building ipatool and fetching go-ios for both architectures…"
dart run tool/fetch_binaries.dart --platform=macos-arm64
dart run tool/fetch_binaries.dart --platform=macos-x64

for tool in ipatool ios; do
  arm="tools/bin/macos-arm64/$tool"
  x64="tools/bin/macos-x64/$tool"
  if lipo -info "$arm" 2>/dev/null | grep -q "x86_64" && lipo -info "$arm" | grep -q "arm64"; then
    # Already universal (the go-ios release ships one binary for both).
    cp "$arm" "$universal/$tool"
  else
    lipo -create "$arm" "$x64" -output "$universal/$tool"
  fi
  chmod +x "$universal/$tool"
  lipo -info "$universal/$tool"
done

echo "Building the app…"
flutter build macos --release

# Helper tools go next to the app executable: code in Contents/Resources is
# not treated as part of the bundle by code signing and Gatekeeper, so a
# downloaded build had each tool blocked on its own.
helpers="$app/Contents/MacOS"
cp "$universal/ipatool" "$universal/ios" "$helpers/"
chmod +x "$helpers/ipatool" "$helpers/ios"

entitlements="macos/Runner/Release.entitlements"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing with: $SIGN_IDENTITY"
  # Hardened runtime and a timestamp are required for notarization.
  sign=(codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY")
else
  echo "SIGN_IDENTITY is not set: ad-hoc signature. A downloaded copy needs"
  echo "\"Open Anyway\" once, or: xattr -dr com.apple.quarantine /Applications/Returner.app"
  sign=(codesign --force --sign -)
fi
# Inside out, without --deep: frameworks, then the helper tools, then the
# bundle itself with the app's entitlements (the tools get none).
shopt -s nullglob
for nested in "$app"/Contents/Frameworks/*.framework "$app"/Contents/Frameworks/*.dylib; do
  "${sign[@]}" "$nested"
done
shopt -u nullglob
for tool in ipatool ios; do
  "${sign[@]}" --identifier "ru.returner.$tool" "$helpers/$tool"
done
"${sign[@]}" --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"

echo "Creating ${dmg}…"
rm -f "$dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/Returner.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Returner $version" -srcfolder "$staging" -ov -format UDZO "$dmg"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
  echo "Signed. Notarize it next: xcrun notarytool submit \"$dmg\" --wait, then xcrun stapler staple."
fi
echo "Done: $dmg"
