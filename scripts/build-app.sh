#!/usr/bin/env bash
# Builds Rokkin.app into ./build. Requires Xcode or the Command Line Tools (macOS 13+).
# Uses SwiftPM when it works, and falls back to calling swiftc directly. The swiftc path also
# picks a macOS SDK that the compiler can actually read (a half-updated Command Line Tools can
# ship an SDK newer than its compiler). Override with: SWIFTC=/path/to/swiftc SDKROOT=/path/to/sdk
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Rokkin.app"
OBJ="build/obj"
BIN=""
mkdir -p build

# ---- toolchain / SDK selection -------------------------------------------------------------

swiftlang_of_compiler() {
  "$1" --version 2>/dev/null | sed -n 's/.*swiftlang-\([0-9.]*\).*/\1/p' | head -1
}

swiftlang_of_sdk() {
  local f
  for f in "$1"/usr/lib/swift/Swift.swiftmodule/*.swiftinterface; do
    [ -f "$f" ] || continue
    sed -n 's/^\/\/ swift-compiler-version:.*swiftlang-\([0-9.]*\).*/\1/p' "$f" | head -1
    return 0
  done
}

# true when $1 <= $2 (version order)
ver_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }

find_toolchain() {
  if [ -n "${SWIFTC:-}" ] && [ -n "${SDKROOT:-}" ]; then
    SDK="$SDKROOT"
    echo "    (指定) swiftc: $SWIFTC / SDK: $SDK"
    return 0
  fi
  local devs=() d cand sc cv sdk sv best bestv
  devs+=("$(xcode-select -p 2>/dev/null || true)")
  for d in /Applications/Xcode*.app/Contents/Developer; do
    [ -d "$d" ] && devs+=("$d")
  done
  for d in "${devs[@]}"; do
    [ -n "$d" ] || continue
    sc=""
    for cand in "$d/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" "$d/usr/bin/swiftc"; do
      if [ -x "$cand" ]; then sc="$cand"; break; fi
    done
    [ -n "$sc" ] || continue
    cv="$(swiftlang_of_compiler "$sc")"
    echo "    toolchain: $sc (swiftlang-${cv:-?})"
    best=""
    bestv=""
    for sdk in "$d"/SDKs/MacOSX*.sdk "$d"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk; do
      [ -d "$sdk" ] || continue
      sv="$(swiftlang_of_sdk "$sdk")"
      if [ -n "$sv" ] && [ -n "$cv" ] && ver_le "$sv" "$cv"; then
        echo "      ok  $sdk (swiftlang-$sv)"
        if [ -z "$bestv" ] || ver_le "$bestv" "$sv"; then best="$sdk"; bestv="$sv"; fi
      else
        echo "      NG  $sdk (swiftlang-${sv:-?})"
      fi
    done
    if [ -n "$best" ]; then
      SWIFTC="$sc"
      SDK="$best"
      echo "    -> 使用: $SWIFTC + $SDK"
      return 0
    fi
  done
  return 1
}

# ---- builds --------------------------------------------------------------------------------

build_with_spm() {
  echo "==> swift build (release)"
  swift build -c release --product Rokkin || return 1
  BIN="$(swift build -c release --show-bin-path)/Rokkin"
}

build_with_swiftc() {
  echo "==> swiftc で直接ビルドします"
  if ! find_toolchain; then
    echo
    echo "!! このコンパイラで読めるmacOS SDKが見つかりませんでした。"
    echo "   Command Line Tools の更新が途中で止まっている可能性があります。次のどちらかで直ります："
    echo "   1) システム設定 > 一般 > ソフトウェアアップデート で Command Line Tools の更新を最後まで入れる"
    echo "   2) sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
    exit 1
  fi
  rm -rf "$OBJ"
  mkdir -p "$OBJ"
  local target
  target="$(uname -m)-apple-macos13.0"
  local common=(-sdk "$SDK" -target "$target" -swift-version 5 -O -whole-module-optimization)

  echo "    compile RokkinCore"
  "$SWIFTC" "${common[@]}" -parse-as-library -module-name RokkinCore \
    -emit-module -emit-module-path "$OBJ/RokkinCore.swiftmodule" \
    -emit-library -static -o "$OBJ/libRokkinCore.a" \
    Sources/RokkinCore/*.swift

  echo "    compile Rokkin"
  "$SWIFTC" "${common[@]}" -parse-as-library -module-name Rokkin \
    -I "$OBJ" -L "$OBJ" -lRokkinCore \
    -o "$OBJ/Rokkin" \
    Sources/Rokkin/*.swift Sources/Rokkin/Views/*.swift
  BIN="$OBJ/Rokkin"
}

if [[ "${1:-}" == "--swiftc" ]]; then
  build_with_swiftc
elif ! build_with_spm; then
  echo
  echo "!! swift build が失敗しました。swiftc での直接ビルドに切り替えます。"
  build_with_swiftc
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rokkin"
cp Support/Info.plist "$APP/Contents/Info.plist"
# App icon: compile the iconset with iconutil when available, else use the prebuilt .icns
if command -v iconutil >/dev/null 2>&1 && iconutil -c icns Support/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  :
else
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature so macOS can remember the Automation permission for this build.
codesign --force --deep --sign - "$APP" >/dev/null

echo
echo "Built: $(pwd)/$APP"
echo "Install:  ditto \"$APP\" /Applications/Rokkin.app && open /Applications/Rokkin.app"
