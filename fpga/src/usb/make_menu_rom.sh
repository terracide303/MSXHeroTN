#!/bin/bash
# Build menu_rom.vh -- the OSD menu that sysctrl streams to FPGA-Companion on
# CMD 8. The companion gunzips it and renders the menu described inside.
#
#   ./make_menu_rom.sh
#
# The XML is minified first: comments and indentation are for whoever reads the
# file in the repo, and they do not fit in a 1K ROM once compressed.
#
# Output is a .hex for $readmemh, matching how NanoMig does it. Gowin infers
# that as BSRAM; a generated case statement was tried and cost LUTs on a design
# already at 88% CLS.
set -euo pipefail
cd "$(dirname "$0")"

SRC=msxnano.xml
OUT=msxnano_xml.hex
CAP=1024

python3 - "$SRC" > /tmp/menu_min.xml <<'PY'
import re, sys
x = open(sys.argv[1], encoding='utf-8').read()
x = re.sub(r'<!--.*?-->', '', x, flags=re.S)
x = re.sub(r'>\s+<', '><', x)
x = re.sub(r'[ \t]+', ' ', x)
sys.stdout.write(x.strip())
PY

gzip -9 -n -c /tmp/menu_min.xml > /tmp/menu_min.xml.gz
SIZE=$(wc -c < /tmp/menu_min.xml.gz | tr -d ' ')

if [ "$SIZE" -gt "$CAP" ]; then
    echo "ERROR: $SIZE bytes gzipped, ROM holds $CAP."
    echo "Trim the menu, or widen menu_rom_addr in sys_ctrl.v."
    exit 1
fi

xxd -c1 -p /tmp/menu_min.xml.gz > "$OUT" 

echo "$OUT: $SIZE bytes gzipped, $((CAP - SIZE)) spare"
