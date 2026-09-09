// =============================================================================
// 03 - Intermediaries (law firms, banks, agents)             14,110 rows
// =============================================================================
// Source: raw/nodes.intermediary.csv
// 704 rows carry several ";"-separated country codes (e.g. "CHE;GBR"), so
// `countries_list` / `country_codes_list` are stored alongside the raw strings.
// =============================================================================

:auto LOAD CSV WITH HEADERS FROM 'file:///panama/nodes.intermediary.csv' AS row
CALL {
  WITH row
  CREATE (i:Node:Intermediary)
  SET i.node_id            = toInteger(row.node_id),
      i.name               = CASE row.name          WHEN '' THEN null ELSE row.name          END,
      i.country_codes      = CASE row.country_codes WHEN '' THEN null ELSE row.country_codes END,
      i.countries          = CASE row.countries     WHEN '' THEN null ELSE row.countries     END,
      i.country_codes_list = CASE row.country_codes WHEN '' THEN null ELSE split(row.country_codes, ';') END,
      i.countries_list     = CASE row.countries     WHEN '' THEN null ELSE split(row.countries, ';')     END,
      i.status             = CASE row.status        WHEN '' THEN null ELSE row.status        END,
      i.sourceID           = CASE row.sourceID      WHEN '' THEN null ELSE row.sourceID      END,
      i.valid_until        = CASE row.valid_until   WHEN '' THEN null ELSE row.valid_until   END,
      i.note               = CASE row.note          WHEN '' THEN null ELSE row.note          END
} IN TRANSACTIONS OF 10000 ROWS;
