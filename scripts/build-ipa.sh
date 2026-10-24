#!/bin/zsh
# Builds an unsigned build/Torrly.ipa for sideloading with AltStore or SideStore, which sign it with the
# installer's own (free) Apple ID. Needs the engine (scripts/build-engine.sh) and xcodegen.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

[[ -d Vendor/TorrlyEngine.xcframework ]] || ./scripts/build-engine.sh
xcodegen generate

xcodebuild -project Torrly.xcodeproj -scheme Torrly -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/ipa \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build

STAGE="$ROOT/build/ipa/stage"
rm -rf "$STAGE" "$ROOT/build/Torrly.ipa"
mkdir -p "$STAGE/Payload"
cp -R "$ROOT/build/ipa/Build/Products/Release-iphoneos/Torrly.app" "$STAGE/Payload/"
(cd "$STAGE" && zip -qry "$ROOT/build/Torrly.ipa" Payload)
echo "Built $ROOT/build/Torrly.ipa"
