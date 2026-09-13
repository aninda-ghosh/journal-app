#!/bin/bash
# Journal — build and verify.
#
# Double-click this file to do everything: build the app, then check it works.
# Or from Terminal, to do one part at a time:
#
#   ./make.command              build, then run every check
#   ./make.command build        produce the dmg, nothing else
#   ./make.command test         run the app's checks
#   ./make.command dictation    prove Whisper actually transcribes
#   ./make.command engine       build only the speech engine and model
#   ./make.command clean        throw away build output and start over
#
# Nothing here is destructive to your journal. `clean` only removes things
# this script can rebuild.

cd "$(dirname "$0")" || exit 1

WHISPER_MODEL="small.en-q5_1"
MODEL_FILE="native/models/ggml-$WHISPER_MODEL.bin"
HELPER="native/build/transcriber"

COMMAND="${1:-all}"
STARTED=$(date +%s)

# What happened, for the summary at the end.
RESULTS=()
FAILED=0

# ---------------------------------------------------------------- reporting

bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
dim()   { printf "\033[2m%s\033[0m\n" "$1"; }

step()  { echo; bold "▸ $1"; }
pass()  { printf "  \033[32m✓\033[0m %s\n" "$1"; RESULTS+=("ok|$1"); }
skip()  { printf "  \033[2m—\033[0m %s\n" "$1"; RESULTS+=("skip|$1"); }
warn()  { printf "  \033[33m!\033[0m %s\n" "$1"; RESULTS+=("warn|$1"); }
bad()   { printf "  \033[31m✗\033[0m %s\n" "$1"; RESULTS+=("fail|$1"); FAILED=1; }

# ------------------------------------------------------------ prerequisites

have() { command -v "$1" >/dev/null 2>&1; }

find_node() {
  have node && return 0
  for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.volta/bin"; do
    [ -x "$dir/node" ] && export PATH="$dir:$PATH" && return 0
  done
  return 1
}

check_tools() {
  step "Checking what's installed"

  if find_node; then
    pass "Node $(node -v)"
  else
    bad "Node.js is missing — install it from https://nodejs.org, or: brew install node"
    return 1
  fi

  if have git; then
    pass "git"
  else
    bad "git is missing — run: xcode-select --install"
    return 1
  fi

  if have cmake; then
    pass "cmake $(cmake --version | head -1 | awk '{print $3}')"
  else
    warn "cmake is missing — dictation will be skipped. Install it with: brew install cmake"
  fi

  return 0
}

# ------------------------------------------------------------- npm packages

install_deps() {
  step "Build tools"
  if [ -d node_modules ] && [ ! package.json -nt node_modules ]; then
    pass "already installed"
    return 0
  fi
  dim "  installing (slow, once)…"
  if npm install --no-audit --no-fund >/tmp/journal-npm.log 2>&1; then
    touch node_modules
    pass "installed"
  else
    bad "npm install failed — see /tmp/journal-npm.log"
    return 1
  fi
}

# ------------------------------------------------------- the speech engine

build_engine() {
  step "Speech engine"

  if ! have cmake; then
    skip "no cmake, so no dictation in this build"
    return 0
  fi

  # whisper.cpp is a submodule, pinned to a known commit. Cloning without
  # --recursive leaves the folder empty, which is the classic submodule trap —
  # so just fill it in rather than making anyone read an error about it.
  if [ ! -f native/whisper.cpp/CMakeLists.txt ]; then
    dim "  fetching the speech engine…"
    if ! git submodule update --init --recursive native/whisper.cpp 2>/tmp/journal-submodule.log; then
      bad "couldn't fetch the speech engine — see /tmp/journal-submodule.log"
      return 1
    fi
  fi
  pass "whisper.cpp at $(cd native/whisper.cpp && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

  local need_compile=0
  if [ ! -x "$HELPER" ]; then
    need_compile=1
  elif [ native/transcriber.cpp -nt "$HELPER" ] || [ native/CMakeLists.txt -nt "$HELPER" ]; then
    need_compile=1
  fi

  if [ "$need_compile" -eq 0 ]; then
    pass "transcriber already built"
  else
    dim "  compiling (several minutes, once)…"
    if cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release >/tmp/journal-cmake.log 2>&1 \
       && cmake --build native/build -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" \
            --target transcriber >>/tmp/journal-cmake.log 2>&1; then
      # Multi-config generators (Xcode) put it under Release/; single-config
      # ones put it at the top. Normalise, so nothing downstream has to care.
      if [ ! -x "$HELPER" ] && [ -x native/build/Release/transcriber ]; then
        cp native/build/Release/transcriber "$HELPER"
      fi
      if [ ! -x "$HELPER" ]; then
        bad "the engine compiled but the binary is not where expected — see /tmp/journal-cmake.log"
        return 1
      fi
      pass "transcriber built ($(du -h "$HELPER" | cut -f1))"
    else
      bad "the speech engine wouldn't compile — see /tmp/journal-cmake.log"
      return 1
    fi
  fi

  check_model
}

# The model is not in the repository — it is ~180MB, and git would keep every
# version of it forever. It is downloaded once on the first build, using the
# script that comes with whisper.cpp, and cached thereafter.
check_model() {
  if [ -f "$MODEL_FILE" ] && [ "$(wc -c < "$MODEL_FILE" | tr -d ' ')" -gt 1000000 ]; then
    pass "model present ($(du -h "$MODEL_FILE" | cut -f1))"
    return 0
  fi

  dim "  downloading the speech model (~180MB, once)…"
  mkdir -p native/models

  if bash native/whisper.cpp/models/download-ggml-model.sh "$WHISPER_MODEL" native/models \
       >/tmp/journal-model.log 2>&1 && [ -f "$MODEL_FILE" ]; then
    pass "model downloaded ($(du -h "$MODEL_FILE" | cut -f1))"
  else
    bad "couldn't download the speech model — see /tmp/journal-model.log"
    echo "        It needs a network connection the first time only."
    return 1
  fi
}

# ------------------------------------------------------------------ checks

run_tests() {
  step "App checks"

  if [ ! -d node_modules ]; then
    bad "build tools aren't installed — run ./make.command build first"
    return 1
  fi

  local log=/tmp/journal-test.log
  dim "  booting the real app and driving it (a couple of minutes)…"

  if node tools/smoke-test.js >"$log" 2>&1; then
    pass "$(grep -oE '[0-9]+ passed' "$log" | tail -1), none failed"
  else
    local summary
    summary=$(grep -oE '[0-9]+ passed, [0-9]+ failed' "$log" | tail -1)
    # NB: an apostrophe inside ${var:-default} opens a quote even within
    # double quotes, so keep this default plain.
    bad "${summary:-the checks stopped early} — see $log"
    grep -E '^ FAIL' "$log" | head -8 | sed 's/^/      /'
    return 1
  fi
}

check_dictation() {
  step "Dictation"

  if [ ! -x "$HELPER" ]; then
    skip "not built — install cmake and run ./make.command engine"
    return 0
  fi
  if [ ! -f "$MODEL_FILE" ] || [ "$(wc -c < "$MODEL_FILE" | tr -d ' ')" -lt 1000000 ]; then
    skip "no speech model — see ./make.command engine"
    return 0
  fi

  # This is the one check that can't be faked: real audio, real model,
  # real words. It's why this script exists.
  local log=/tmp/journal-dictation.log
  dim "  transcribing a known recording…"

  if node tools/whisper-check.js >"$log" 2>&1; then
    local heard
    heard=$(grep final "$log" | head -1 | sed -E 's/.*final[[:space:]]+//' | cut -c1-56)
    pass "Whisper transcribes it: $heard…"
  else
    bad "Whisper didn't transcribe correctly — see $log"
    tail -6 "$log" | sed 's/^/      /'
    return 1
  fi
}

# ------------------------------------------------------------------- the app

build_app() {
  step "The app"
  if [ ! -x "$HELPER" ]; then
    warn "transcriber helper is not built ($HELPER) — the packaged app will not have local dictation"
  fi
  dim "  packaging…"

  if npm run dist >/tmp/journal-dist.log 2>&1; then
    local dmg
    dmg=$(ls -t dist/*.dmg 2>/dev/null | head -1)
    if [ -n "$dmg" ]; then
      pass "$dmg ($(du -h "$dmg" | cut -f1))"
    else
      warn "built, but no dmg appeared in dist/"
    fi
  else
    bad "packaging failed — see /tmp/journal-dist.log"
    return 1
  fi
}

clean() {
  step "Cleaning"
  rm -rf dist native/build
  pass "removed dist/ and native/build/"
  dim "  kept node_modules, whisper.cpp and the model — they're slow to fetch."
  dim "  to remove those too:  rm -rf node_modules native/whisper.cpp native/models"
}

# ------------------------------------------------------------------ summary

summary() {
  local elapsed=$(( $(date +%s) - STARTED ))
  echo
  bold "───────────────────────────────────────────────"
  for entry in "${RESULTS[@]}"; do
    local kind="${entry%%|*}" text="${entry#*|}"
    case "$kind" in
      ok)   printf "  \033[32m✓\033[0m %s\n" "$text" ;;
      skip) printf "  \033[2m— %s\033[0m\n" "$text" ;;
      warn) printf "  \033[33m!\033[0m %s\n" "$text" ;;
      fail) printf "  \033[31m✗\033[0m %s\n" "$text" ;;
    esac
  done
  bold "───────────────────────────────────────────────"

  printf "  %dm %ds\n\n" $((elapsed / 60)) $((elapsed % 60))

  local skipped=0
  for entry in "${RESULTS[@]}"; do
    case "${entry%%|*}" in skip|warn) skipped=$((skipped + 1)) ;; esac
  done

  if [ "$FAILED" -eq 1 ]; then
    printf "\033[31mSomething did not work.\033[0m The lines marked ✗ say where to look.\n"
  elif [ "$skipped" -gt 0 ]; then
    # Don't say "all good" when the part you care about never ran.
    printf "\033[33mNothing failed, but %d step(s) were skipped.\033[0m\n" "$skipped"
    printf "See the — and ! lines above; they say what is missing.\n"
  else
    printf "\033[32mAll good.\033[0m\n"
  fi

  local dmg
  dmg=$(ls -t dist/*.dmg 2>/dev/null | head -1)
  if [ "$FAILED" -eq 0 ] && [ -n "$dmg" ]; then
    echo "Open $dmg and drag Journal to your Applications folder."
  fi
}

# --------------------------------------------------------------------- main

echo
bold "Journal — $COMMAND"
dim "$(pwd)"

case "$COMMAND" in
  all)
    check_tools && install_deps && build_engine
    run_tests
    check_dictation
    [ "$FAILED" -eq 0 ] && build_app
    ;;
  build)
    check_tools && install_deps && build_engine && build_app
    ;;
  engine)
    check_tools && build_engine && check_dictation
    ;;
  test)
    check_tools && install_deps && run_tests
    ;;
  dictation)
    check_tools && check_dictation
    ;;
  clean)
    clean
    ;;
  *)
    echo
    echo "Don't know how to '$COMMAND'. Try one of:"
    echo "  ./make.command             build and check everything"
    echo "  ./make.command build       just produce the dmg"
    echo "  ./make.command test        just run the app's checks"
    echo "  ./make.command dictation   just check Whisper transcribes"
    echo "  ./make.command engine      just build the speech engine"
    echo "  ./make.command clean       start the build fresh"
    echo
    exit 1
    ;;
esac

summary

# Double-clicked from Finder: keep the window open so the summary is readable.
if [ -z "$1" ]; then
  echo
  read -r -p "Press return to close."
fi

exit "$FAILED"
