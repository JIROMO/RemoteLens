#!/bin/bash
# RemoteLens.app をビルドする。App Store 非公開・完全ローカル運用のため ad-hoc 署名。
# 使い方:
#   ./build.sh            ビルドのみ（build/RemoteLens.app）
#   ./build.sh install    ビルドして /Applications へコピー
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/RemoteLens.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/RemoteLens "$APP/Contents/MacOS/RemoteLens"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "✅ ビルド完了: $APP"

if [[ "${1:-}" == "install" ]]; then
    rm -rf /Applications/RemoteLens.app
    cp -R "$APP" /Applications/RemoteLens.app
    echo "✅ インストール完了: /Applications/RemoteLens.app"
fi
