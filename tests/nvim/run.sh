#!/usr/bin/env bash
# Tests topos-bible.nvim in headless Neovim: once with the quickfix list, and once with Telescope
# if it is installed (PLUGINS is the folder with plenary.nvim and telescope.nvim; lazy.nvim's by
# default). The binaries are built from checkouts: topos from TOPOS (default ../../rust/topos) and
# biblix-lsp from BIBLIX (default ../../rust/biblix), next to this repository in ~/Development
# (next to this repository in ~/Development). Run from anywhere: tests/nvim/run.sh
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TOPOS=$(cd "${TOPOS:-$REPO/../../rust/topos}" && pwd)
BIBLIX=$(cd "${BIBLIX:-$REPO/../../rust/biblix}" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cargo build -q --manifest-path "$TOPOS/Cargo.toml" -p topos-bible-cli
cargo build -q --manifest-path "$BIBLIX/Cargo.toml" -p biblix-lsp

mkdir -p "$WORK/ws/.git" "$WORK/ws/My Notes" "$WORK/config" "$WORK/cache"
printf 'Jn 3:16 again\nand John 3:14-18\n' > "$WORK/ws/My Notes/a.md"
printf 'John 3, John 2; 3:16, Rom 8:28, Luke 2:1\n' > "$WORK/ws/b.txt"
printf 'See jn 3:16 here\n' > "$WORK/ws/open.txt"
# A book (the `epub` option): an EPUB of two paragraphs, copied into the workspace only while
# its step runs (the CLI's searches read EPUBs too)
python3 - "$WORK/Gill.epub" <<'PY'
import sys, zipfile
page = '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>c</title></head><body><p>Preface</p><p>On grace, see 📖 Rom 8:28 and more.</p></body></html>'
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("mimetype", "application/epub+zip")
    z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr("content.opf", '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Gill</dc:title></metadata><manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>')
    z.writestr("c.xhtml", page)
PY
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
cat > "$WORK/Bibles/BSB/ROM.usx" <<'USX'
<usx version="3.0"><book code="ROM" style="id">x</book>
<chapter number="8" style="c" sid="ROM 8"/>
<para style="p"><verse number="28" style="v" sid="ROM 8:28"/>And we know that God works all things together for good.<verse eid="ROM 8:28"/></para>
<chapter eid="ROM 8"/></usx>
USX
# Another Bible, named KJV (alias AV) in `bibles`, with only John 3:16
mkdir -p "$WORK/Bibles/KJV"
cat > "$WORK/Bibles/KJV/JHN.usx" <<'USX'
<usx version="3.0"><book code="JHN" style="id">x</book>
<chapter number="3" style="c" sid="JHN 3"/>
<para style="p"><verse number="16" style="v" sid="JHN 3:16"/>For God so loved the world, that he gave his only begotten Son.<verse eid="JHN 3:16"/></para>
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
  (cd "$WORK/ws" && env REPO="$REPO" TOPOS="$TOPOS" BIBLIX="$BIBLIX" WORK="$WORK" "$@" timeout 120 nvim --clean --headless -c "luafile $REPO/tests/nvim/test.lua" >/dev/null 2>&1) || true
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
    'blink colors ```topos-bible heading=Jesus and Nicodemus verseNumber=[16]' \
    'callout > [!bible] John 3:16|> Jesus and Nicodemus|> [16] For God so loved the world.' 'book topos-bible://BSB/JHN topos-bible false nofile' \
    'book line [16] For God so loved the world. [17] Jesus said, I did not come to condemn.' \
    'book cursor 4 0' 'book title John' 'woj @lsp.type.wordsOfJesus.topos-bible 16711680' \
    'verse number @lsp.type.verseNumber.topos-bible Special' 'book references 4' 'tag true 4' \
    'bibles BSB|KJV' 'named hover **John 3:16** (KJV) that he gave' 'default hover *BSB*' \
    'missing in KJV John 3:17 does not exist in the KJV' 'set default hover *KJV*' \
    'parallel topos-bible://KJV/JHN [16] For God so loved the world, that he gave his only begotten Son.' \
    'parallel follows John 3' 'health bibles 2' \
    'read topos-bible://BSB/JHN topos-bible' 'read next topos-bible://BSB/ROM topos-bible://BSB/JHN' \
    'read bible topos-bible://KJV/JHN' 'read complete Romans KJV' \
    'move verses JHN:[16] JHN:[17] ROM:[28] JHN:[17] JHN:[16]' 'move chapters ROM:Roma JHN:John ROM:Roma' \
    'move books JHN:John ROM:Roma JHN:John' 'move wrap JHN:John JHN:[16] JHN:[17] JHN:[16]' \
    'read starts lsp 1 topos-bible://BSB/ROM true' \
    'unnamed before 0' 'unnamed after 1 John 3:16' 'unnamed reformat Read John 3:16 today' 'unnamed edited Romans 8:28' 'restarted 1 true true true' \
    'book off true' 'book file topos-file true Rom 8:28 Gill'; do
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
  grep -qxF 'read picker Read BSB 2 John @lsp.type.heading.topos-bible' <<<"$output" || { echo "FAIL (telescope :ToposRead)"; grep '^read picker' <<<"$output"; status=1; }
else
  echo "skipped (telescope): not found in $plugins"
fi
exit $status
