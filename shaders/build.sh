#!/bin/sh
# Compile the fragment shaders to .qsb (Qt's cross-API shader bundle). The
# .qsb files are committed, so users never need qsb; run this after editing a
# .frag. Needs qsb from Qt's shadertools (/usr/lib/qt6/bin/qsb on Arch).
set -e
cd "$(dirname "$0")"
QSB=${QSB:-$(command -v qsb || echo /usr/lib/qt6/bin/qsb)}
for f in *.frag; do
  "$QSB" --qt6 "$f" -o "$f.qsb"
  echo "built $f.qsb"
done
