#!/usr/bin/env bash
# =============================================================================
# Stages raw/*.csv into Neo4j's import directory as import/panama/, so the
# file:///panama/... URLs in the load scripts resolve.
#
#   NEO4J_HOME=/path/to/neo4j ./cypher/stage_csv.sh
#
# The CSVs in raw/ are already clean, so for them this is effectively a copy.
# The backslash-escaping pass exists for anyone re-downloading the source from
# offshoreleaks.icij.org, where the problem is still present:
#
# Neo4j reads CSV with `\` as an escape character by default
# (db.import.csv.legacy_quote_escaping=true - not a dynamic setting, so changing
# it means editing neo4j.conf and restarting). The ICIJ originals contain 15
# rows with a stray backslash. Two of them end a field with one, which escapes
# the field's own closing quote; the parser then runs past the end of the field
# and aborts the whole load:
#
#   nodes.officer.csv   "WANG LI\"               <- hard failure
#   nodes.address.csv   "...JERSEY JE4 8YD\"     <- hard failure
#
#   Neo.DatabaseError.Statement.ExecutionFailed ... there's a field starting
#   with a quote and whereas it ends that quote there seems to be characters in
#   that field after that ending quote. This is what I read: 'WANG LI","CC'
#
# The other 13 fail silently, which is worse: `c\o Levant Law Practice` would
# load as `co Levant Law Practice`. Doubling each backslash makes it a literal
# `\` under that same escaping rule, so values survive verbatim.
#
# raw/ is never modified. 07_verify.cypher asserts the result either way.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW="$(dirname "$HERE")/raw"

NEO4J_HOME="${NEO4J_HOME:-}"
NEO4J_IMPORT="${NEO4J_IMPORT:-${NEO4J_HOME:+$NEO4J_HOME/import}}"
: "${NEO4J_IMPORT:?set NEO4J_HOME (or NEO4J_IMPORT) - e.g. NEO4J_HOME=/opt/neo4j-5.26}"
DEST="$NEO4J_IMPORT/panama"

[ -d "$NEO4J_IMPORT" ] || { echo "import dir not found: $NEO4J_IMPORT (set NEO4J_IMPORT)"; exit 1; }
mkdir -p "$DEST"

total=0
for f in nodes.entity.csv nodes.officer.csv nodes.intermediary.csv nodes.address.csv edges.csv; do
  n=$(grep -c '\\' "$RAW/$f" || true)
  total=$(( total + n ))
  sed 's/\\/\\\\/g' "$RAW/$f" > "$DEST/$f"
  printf '  %-24s -> %s%s\n' "$f" "$DEST/$f" \
    "$( [ "$n" -gt 0 ] && echo "  (${n} backslash row(s) escaped)" )"
done

echo "staged into $DEST"
[ "$total" -eq 0 ] && echo "  (no backslashes found - the CSVs in raw/ are already clean)"
exit 0
