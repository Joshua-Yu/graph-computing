// =============================================================================
// 04 - Addresses                                             93,454 rows
// =============================================================================
// Source: raw/nodes.address.csv
// The `name` and `note` columns are empty for every row in this extract and are
// therefore not written; `address` holds the free-text address line.
// =============================================================================

:auto LOAD CSV WITH HEADERS FROM 'file:///panama/nodes.address.csv' AS row
CALL {
  WITH row
  CREATE (a:Node:Address)
  SET a.node_id       = toInteger(row.node_id),
      a.address       = CASE row.address       WHEN '' THEN null ELSE row.address       END,
      a.country_codes = CASE row.country_codes WHEN '' THEN null ELSE row.country_codes END,
      a.countries     = CASE row.countries     WHEN '' THEN null ELSE row.countries     END,
      a.sourceID      = CASE row.sourceID      WHEN '' THEN null ELSE row.sourceID      END,
      a.valid_until   = CASE row.valid_until   WHEN '' THEN null ELSE row.valid_until   END,
      a.name          = CASE row.name          WHEN '' THEN null ELSE row.name          END,
      a.note          = CASE row.note          WHEN '' THEN null ELSE row.note          END
} IN TRANSACTIONS OF 10000 ROWS;
