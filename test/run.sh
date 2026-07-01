#!/usr/bin/env bash
set -u

ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
BIN="${SMARTCAT_BIN:-$ROOT/bin/smartcat}"
CONFIG="$ROOT/share/smartcat/config.default.yaml"

PASS=0
FAIL=0

GREEN=""; RED=""; RESET=""
if [ -t 1 ]; then GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'; fi

ok()   { PASS=$((PASS + 1)); printf '%s  ok %s%s\n' "$GREEN" "$1" "$RESET"; }
bad()  { FAIL=$((FAIL + 1)); printf '%sNOT ok %s%s\n' "$RED" "$1" "$RESET"; printf '       %s\n' "$2"; }

assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) bad "$1" "[$2] does not contain [$3]" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) bad "$1" "[$2] unexpectedly contains [$3]" ;;
    *) ok "$1" ;;
  esac
}
assert_files_eq() {
  if cmp -s "$2" "$3"; then ok "$1"; else bad "$1" "files [$2] and [$3] differ"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_fakes() {
  local dir="$1"; shift
  mkdir -p "$dir"
  local name
  for name in "$@"; do
    cat > "$dir/$name" <<'EOF'
#!/bin/sh
self="$(basename "$0")"
printf 'FAKE %s ARGS=[%s]\n' "$self" "$*"
if [ ! -t 0 ]; then
  data="$(head -c 300 2>/dev/null)"
  if [ -n "$data" ]; then printf 'FAKE %s STDIN-LEAK<<%s>>\n' "$self" "$data"; fi
fi
exit 0
EOF
    chmod +x "$dir/$name"
  done
}

clean() { tr -cd '\11\12\15\40-\176' | tr -d '\r'; }

run_pty() {
  local cap out i
  out=""
  for i in 1 2 3 4 5; do
    cap="$(mktemp)"
    script -q "$cap" "$@" >/dev/null 2>&1
    out="$(clean < "$cap")"
    rm -f "$cap"
    [ -n "$out" ] && break
  done
  printf '%s' "$out"
}

FAKE_ALL="$TMP/fake_all"
FAKE_BAT="$TMP/fake_bat"
make_fakes "$FAKE_ALL" glow mdcat bat imgcat chafa bsdtar
make_fakes "$FAKE_BAT" bat

MD="$TMP/sample.md"
printf '# Title\n\nSENTINEL-MD-CONTENT\n' > "$MD"
PY="$TMP/sample.py"
printf 'print("SENTINEL-PY")\n' > "$PY"
TXT="$TMP/notes.txt"
printf 'plain text\nwith two lines\n' > "$TXT"
GIF="$TMP/noext_image"
printf 'GIF89a\001\000\001\000\000\377\377\377\054' > "$GIF"
GZ="$TMP/dump.sql.gz"
printf 'SELECT 1; -- SENTINEL-SQL\n' | gzip > "$GZ"
TAR="$TMP/dump.sql.tar"
tar cf "$TAR" -C "$TMP" sample.py
TGZ="$TMP/dump.sql.tgz"
tar czf "$TGZ" -C "$TMP" sample.py
TARGZ="$TMP/dump.sql.tar.gz"
tar czf "$TARGZ" -C "$TMP" sample.py

export SMARTCAT_CONFIG="$CONFIG"
BASE_PATH="/usr/bin:/bin"

echo "== meta =="
assert_contains "version" "$("$BIN" --version)" "smartcat "
assert_contains "help mentions -native" "$("$BIN" --help)" "-native"
assert_contains "init zsh emits wrapper" "$("$BIN" init zsh)" "command smartcat"
assert_contains "init unknown shell errors" "$("$BIN" init fish 2>&1)" "unsupported shell"

echo "== passthrough (no TTY) =="
assert_eq "single file piped equals cat" "$(command cat "$MD")" "$("$BIN" "$MD" | command cat)"
assert_eq "multi file equals cat" "$(command cat "$MD" "$TXT")" "$("$BIN" "$MD" "$TXT" | command cat)"
assert_eq "flag -n equals cat -n" "$(command cat -n "$MD")" "$("$BIN" -n "$MD" | command cat)"
assert_eq "missing file behaves like cat" "$(command cat "$TMP/nope.md" 2>&1)" "$("$BIN" "$TMP/nope.md" 2>&1)"
command cat "$GZ" > "$TMP/gz_via_cat"
"$BIN" "$GZ" > "$TMP/gz_via_smartcat"
assert_files_eq "piped gz stays byte-for-byte (no decompression)" "$TMP/gz_via_cat" "$TMP/gz_via_smartcat"

echo "== TTY rendering selection =="
out="$(PATH="$FAKE_ALL:$BASE_PATH" run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$MD")"
assert_contains "md picks first renderer (glow)" "$out" "FAKE glow ARGS=[$MD]"

out="$(run_pty env PATH="$FAKE_BAT:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$MD")"
assert_contains "md falls back to bat when glow absent" "$out" "FAKE bat ARGS="

out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$PY")"
assert_contains "py uses code handler (bat)" "$out" "FAKE bat ARGS="

out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$GIF")"
assert_contains "extensionless gif detected via mime" "$out" "FAKE imgcat ARGS="

echo "== compressed single files re-render by inner extension =="
out="$(run_pty env PATH="$FAKE_BAT:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$GZ")"
assert_contains "sql.gz decompresses and renders via bat" "$out" "FAKE bat ARGS="
assert_contains "sql.gz picks the inner .sql extension" "$out" "dump.sql]"

out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$TAR")"
assert_contains "sql.tar (uncompressed) is listed as an archive via bsdtar" "$out" "FAKE bsdtar ARGS=[-tvf $TAR]"
assert_not_contains "sql.tar is not decompressed to a temp file" "$out" "FAKE bat"

out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$TGZ")"
assert_contains "sql.tgz (single-word alias) is listed as an archive via bsdtar" "$out" "FAKE bsdtar ARGS=[-tvf $TGZ]"
assert_not_contains "sql.tgz is not decompressed to a temp file" "$out" "FAKE bat"

out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$TARGZ")"
assert_contains "sql.tar.gz (compound suffix) is listed as an archive via bsdtar" "$out" "FAKE bsdtar ARGS=[-tvf $TARGZ]"
assert_not_contains "sql.tar.gz is not decompressed to a temp file" "$out" "FAKE bat"

echo "== regression: stdin must not leak the command list to the renderer =="
leak_probe="$(printf 'CONFIG-LEAK-DATA' | "$FAKE_ALL/glow")"
assert_contains "leak detector is live" "$leak_probe" "STDIN-LEAK<<CONFIG-LEAK-DATA"
out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$MD")"
assert_contains "renderer actually ran" "$out" "FAKE glow ARGS=[$MD]"
assert_not_contains "renderer receives no leaked stdin" "$out" "STDIN-LEAK"
assert_not_contains "renderer not fed config tokens" "$out" "mdcat {file}"

echo "== -native forces vanilla cat =="
out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" -native "$MD")"
assert_contains "-native shows raw content" "$out" "SENTINEL-MD-CONTENT"
assert_not_contains "-native does not render" "$out" "FAKE glow"

echo "== hint + plain fallback when no renderer is installed =="
out="$(run_pty env PATH="$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" "$MD")"
assert_contains "hint printed" "$out" "brew install glow"
assert_contains "content still shown" "$out" "SENTINEL-MD-CONTENT"
nl=$'\n'
assert_contains "hint follows content after a blank line" "$out" "SENTINEL-MD-CONTENT${nl}${nl}smartcat:"
assert_contains "content precedes hint" "${out%%smartcat:*}" "SENTINEL-MD-CONTENT"

echo "== status =="
sout="$(PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" -status)"
assert_contains "status has header" "$sout" "ACTIVE"
assert_contains "status lists markdown" "$sout" "markdown"
assert_contains "status lists pdf" "$sout" "pdf"
assert_contains "status shows active renderer" "$sout" "glow"
sout2="$(PATH="$BASE_PATH" SMARTCAT_CONFIG="$CONFIG" "$BIN" --status)"
assert_contains "status marks missing renderers" "$sout2" "MISSING"
assert_contains "status prints missing hints" "$sout2" "brew install glow"

echo "== config resolution =="
ALT="$TMP/alt.yaml"
cat > "$ALT" <<'EOF'
handlers:
  markdown:
    extensions: [md]
    commands:
      - chafa {file}
    hint: "alt hint"
EOF
out="$(run_pty env PATH="$FAKE_ALL:$BASE_PATH" SMARTCAT_CONFIG="$ALT" "$BIN" "$MD")"
assert_contains "SMARTCAT_CONFIG override is used" "$out" "FAKE chafa ARGS="

echo
printf 'passed: %d, failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
