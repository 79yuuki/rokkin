#!/bin/bash
# Double-click (or run) to build Rokkin.app and write the result to build.log
cd "$(dirname "$0")/.." || exit 1
{
  echo "== $(date)"
  xcode-select -p
  swift --version
  ./scripts/build-app.sh --swiftc
  echo "EXIT:$?"
} > build.log 2>&1
tail -5 build.log
echo
echo "終わりました。このウィンドウは閉じてOKです。"
