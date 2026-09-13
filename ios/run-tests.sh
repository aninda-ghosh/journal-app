#!/bin/bash
# Every iPhone verification suite, in one command.
#
# They are standalone binaries rather than an XCTest target, so each one is a
# swiftc invocation over the sources it needs. Run from anywhere; paths are
# resolved against the repository root, because the format suite reads
# spec/fixtures/ from there.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SWIFTC=(xcrun swiftc)
command -v xcrun >/dev/null 2>&1 || SWIFTC=(swiftc)

mkdir -p .cache/swift .cache/clang
FAILED=0

run() {
  local name="$1"; shift
  local out=".cache/verify_${name}"
  printf '\n\033[1m▸ %s\033[0m\n' "$name"
  if ! "${SWIFTC[@]}" -parse-as-library -module-cache-path .cache/swift -Xcc -fmodules-cache-path=.cache/clang "$@" -o "$out"; then
    printf '  \033[31m✗\033[0m %s did not compile\n' "$name"
    FAILED=1
    return
  fi
  if "$out"; then
    printf '  \033[32m✓\033[0m %s\n' "$name"
  else
    printf '  \033[31m✗\033[0m %s\n' "$name"
    FAILED=1
  fi
}

run format \
  ios/Tests/VerifyFormat.swift \
  ios/Journal/Models/Entry.swift

run entry \
  ios/Tests/VerifyEntry.swift \
  ios/Journal/Models/Entry.swift

run storage \
  ios/Tests/VerifyStorage.swift \
  ios/Journal/Models/Entry.swift \
  ios/Journal/Models/JournalStorage.swift

run image \
  ios/Tests/VerifyImageProcessor.swift \
  ios/Journal/Media/ImageProcessor.swift \
  ios/Journal/Models/Entry.swift \
  ios/Journal/Models/JournalStorage.swift

run dictation \
  ios/Tests/VerifyDictationEngine.swift \
  ios/Journal/Audio/DictationEngine.swift

echo
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mAll iPhone suites passed.\033[0m\n'
else
  printf '\033[31mSomething failed.\033[0m\n'
fi
exit "$FAILED"
