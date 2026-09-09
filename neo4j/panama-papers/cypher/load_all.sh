#!/usr/bin/env bash
# =============================================================================
# Loads the Panama Papers extract in raw/ into Neo4j via cypher-shell.
#
#   NEO4J_HOME=/path/to/neo4j NEO4J_PASSWORD=secret ./cypher/load_all.sh
#
# Environment (all optional except the password):
#   NEO4J_HOME      Neo4j install dir (required unless NEO4J_IMPORT is set)
#   NEO4J_IMPORT    Import dir the CSVs are staged into. Default $NEO4J_HOME/import
#   NEO4J_URI       Default bolt://localhost:7687
#   NEO4J_USER      Default neo4j
#   NEO4J_PASSWORD  Required
#   NEO4J_DATABASE  Default neo4j
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NEO4J_HOME="${NEO4J_HOME:-}"
NEO4J_IMPORT="${NEO4J_IMPORT:-${NEO4J_HOME:+$NEO4J_HOME/import}}"
: "${NEO4J_IMPORT:?set NEO4J_HOME (or NEO4J_IMPORT) - e.g. NEO4J_HOME=/opt/neo4j-5.26}"
URI="${NEO4J_URI:-bolt://localhost:7687}"
USER="${NEO4J_USER:-neo4j}"
DB="${NEO4J_DATABASE:-neo4j}"
: "${NEO4J_PASSWORD:?set NEO4J_PASSWORD}"

SHELL_BIN="$(command -v cypher-shell || echo "$NEO4J_HOME/bin/cypher-shell")"
[ -x "$SHELL_BIN" ] || { echo "cypher-shell not found (set NEO4J_HOME)"; exit 1; }
[ -d "$NEO4J_IMPORT" ] || { echo "import dir not found: $NEO4J_IMPORT"; exit 1; }

echo "==> staging CSVs into $NEO4J_IMPORT/panama/"
NEO4J_HOME="$NEO4J_HOME" NEO4J_IMPORT="$NEO4J_IMPORT" "$HERE/stage_csv.sh"

run() {
  echo "==> $1"
  "$SHELL_BIN" -a "$URI" -u "$USER" -p "$NEO4J_PASSWORD" -d "$DB" \
               --format plain -f "$HERE/$1"
}

run 00_constraints.cypher
run 01_load_entities.cypher
run 02_load_officers.cypher
run 03_load_intermediaries.cypher
run 04_load_addresses.cypher
run 05_load_relationships.cypher
run 06_indexes.cypher
run 07_verify.cypher

echo "==> done"
