#!/usr/bin/env bash
# Tests topos-bible.nvim in headless Neovim: once with the quickfix list, and once with Telescope
# if it is installed (PLUGINS is the folder with plenary.nvim and telescope.nvim; lazy.nvim's by
# default). The binaries are built from a topos checkout: TOPOS, by default ../../rust/topos
# (next to this repository in ~/Development). Run from anywhere: tests/nvim/run.sh
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TOPOS=$(cd "${TOPOS:-$REPO/../../rust/topos}" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cargo build -q --manifest-path "$TOPOS/Cargo.toml" -p topos-lsp -p topos-bible-cli

mkdir -p "$WORK/ws/.git" "$WORK/ws/My Notes" "$WORK/config" "$WORK/cache"
printf 'Jn 3:16 again\nand John 3:14-18\n' > "$WORK/ws/My Notes/a.md"
printf 'John 3, John 2; 3:16, Rom 8:28, Luke 2:1\n' > "$WORK/ws/b.txt"
printf 'See jn 3:16 here\n' > "$WORK/ws/open.txt"
# A Bible: a folder of USX files
mkdir -p "$WORK/Bibles/BSB"
cat > "$WORK/Bibles/BSB/JHN.usx" <<'USX'
<?xml version="1.0" encoding="utf-8"?>
<usx version="3.0"><book code="JHN" style="id">x</book>
<para style="mt1">John</para>
<chapter number="3" style="c" sid="JHN 3"/>
<para style="s1">Jesus and Nicodemus</para>
<para style="p"><verse number="16" style="v" sid="JHN 3:16"/>For God so loved the world. <verse eid="JHN 3:16"/><verse number="17" style="v" sid="JHN 3:17"/>Jesus said, <char style="wj">I did not come to condemn.</char><verse eid="JHN 3:17"/></para>
<chapter eid="JHN 3"/></usx>
USX

expected='lsp topos hints true
diagnostic HINT reference John 3:16
search Bible references 7
query topos -g Gospels --exclude-book Luke 5
explicit Search "John 3:16" for explicit overlap 4
exact at cursor Search "John 3:16" for exact overlap 2
any Search "John 3" for any overlap 5
inside Search inside "John 3" 4
complete flags "Pauline Epistles"
complete ref 3:10|3:11|3:12
code action Search "John 3:16" for any overlap Search "John 3:16" for any overlap 5
reformat Reformat as "John 3:16" See John 3:16 here'

run() {
  rm -f "$WORK/out.txt"
  (cd "$WORK/ws" && env REPO="$REPO" TOPOS="$TOPOS" WORK="$WORK" "$@" timeout 120 nvim --clean --headless -c "luafile $REPO/tests/nvim/test.lua" >/dev/null 2>&1) || true
  cat "$WORK/out.txt"
}

status=0
check() {
  local name=$1 output=$2
  if grep -q '^ERROR' <<<"$output" || [[ "$(head -n 12 <<<"$output")" != "$expected" ]]; then
    echo "FAIL ($name):"
    diff <(echo "$expected") <(head -n 12 <<<"$output") || true
    grep '^ERROR' <<<"$output" || true
    status=1
  else
    echo "ok ($name)"
  fi
  # :ToposLspStart starts the server in an unnamed buffer with no file type, then restarts it
  # The Bible: hover text, go-to-definition opens the book, colors, and references from a verse
  for line in 'hover text Jesus and Nicodemus' \
    'hover colors heading=Jesus and Nicodemus verseNumber=[16]' \
    'verse hover **John 3:16**  4 references in 3 files' 'declaration true' \
    'callout > [!bible] John 3:16|> Jesus and Nicodemus|> [16] For God so loved the world.' 'book topos-bible://BSB/JHN topos-bible false nofile' \
    'book line [16] For God so loved the world. [17] Jesus said, I did not come to condemn.' \
    'book cursor 4 0' 'book title John' 'woj @lsp.type.wordsOfJesus.topos-bible 16711680' \
    'verse number @lsp.type.verseNumber.topos-bible Special' 'book references 4' 'tag true 4' \
    'unnamed before 0' 'unnamed after 1 John 3:16' 'unnamed reformat Read John 3:16 today' 'unnamed edited Romans 8:28' 'restarted 1 true true true'; do
    if ! grep -qxF "$line" <<<"$output"; then
      echo "FAIL ($name): expected '$line'"
      grep -E '^(unnamed|restarted|ERROR)' <<<"$output" || true
      status=1
    fi
  done
}

check quickfix "$(run)"
plugins=${PLUGINS:-$HOME/.local/share/nvim/lazy}
if [[ -d "$plugins/telescope.nvim" && -d "$plugins/plenary.nvim" ]]; then
  output=$(run WITH_TELESCOPE=1 PLUGINS="$plugins")
  check telescope "$output"
  grep -q 'telescope ext Search "Rom 8:28" for explicit overlap 1' <<<"$output" || { echo "FAIL (telescope extension)"; status=1; }
else
  echo "skipped (telescope): not found in $plugins"
fi
exit $status
