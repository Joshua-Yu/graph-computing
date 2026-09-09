// =============================================================================
// 02 - Officers (shareholders, directors, beneficiaries)    238,402 rows
// =============================================================================
// Source: raw/nodes.officer.csv
// Note the node_id prefixes differ (12*, 13*, 15*) but all rows in this file
// are officers, so they share the single :Officer label.
// =============================================================================

:auto LOAD CSV WITH HEADERS FROM 'file:///panama/nodes.officer.csv' AS row
CALL {
  WITH row
  CREATE (o:Node:Officer)
  SET o.node_id       = toInteger(row.node_id),
      o.name          = CASE row.name          WHEN '' THEN null ELSE row.name          END,
      o.country_codes = CASE row.country_codes WHEN '' THEN null ELSE row.country_codes END,
      o.countries     = CASE row.countries     WHEN '' THEN null ELSE row.countries     END,
      o.sourceID      = CASE row.sourceID      WHEN '' THEN null ELSE row.sourceID      END,
      o.valid_until   = CASE row.valid_until   WHEN '' THEN null ELSE row.valid_until   END,
      o.note          = CASE row.note          WHEN '' THEN null ELSE row.note          END
} IN TRANSACTIONS OF 10000 ROWS;
