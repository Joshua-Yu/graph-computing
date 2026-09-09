// =============================================================================
// 01 - Entities (offshore companies, trusts, foundations)   213,634 rows
// =============================================================================
// Source: raw/nodes.entity.csv
// Dates arrive as dd-MMM-yyyy (e.g. 23-MAR-2006) and are converted to a real
// Cypher date. Empty CSV cells become null, and SET-ting null simply leaves the
// property off the node - so no empty strings are stored.
//
// `closed_date` and `company_type` are empty for every row in this extract;
// they are kept in the script so a refreshed dump loads them automatically.
// =============================================================================

:auto LOAD CSV WITH HEADERS FROM 'file:///panama/nodes.entity.csv' AS row
CALL {
  WITH row
  WITH row, {JAN:'01', FEB:'02', MAR:'03', APR:'04', MAY:'05', JUN:'06',
             JUL:'07', AUG:'08', SEP:'09', OCT:'10', NOV:'11', DEC:'12'} AS mm
  WITH row,
       [d IN [row.incorporation_date, row.inactivation_date,
              row.struck_off_date,    row.closed_date] |
          CASE WHEN d IS NULL OR d = '' THEN null
               ELSE date(right(d, 4) + '-' + mm[substring(d, 3, 3)] + '-' + left(d, 2))
          END] AS dates
  CREATE (e:Node:Entity)
  SET e.node_id                  = toInteger(row.node_id),
      e.name                     = CASE row.name                     WHEN '' THEN null ELSE row.name                     END,
      e.jurisdiction             = CASE row.jurisdiction             WHEN '' THEN null ELSE row.jurisdiction             END,
      e.jurisdiction_description = CASE row.jurisdiction_description WHEN '' THEN null ELSE row.jurisdiction_description END,
      e.country_codes            = CASE row.country_codes            WHEN '' THEN null ELSE row.country_codes            END,
      e.countries                = CASE row.countries                WHEN '' THEN null ELSE row.countries                END,
      e.ibcRUC                   = CASE row.ibcRUC                   WHEN '' THEN null ELSE row.ibcRUC                   END,
      e.status                   = CASE row.status                   WHEN '' THEN null ELSE row.status                   END,
      e.company_type             = CASE row.company_type             WHEN '' THEN null ELSE row.company_type             END,
      e.service_provider         = CASE row.service_provider         WHEN '' THEN null ELSE row.service_provider         END,
      e.sourceID                 = CASE row.sourceID                 WHEN '' THEN null ELSE row.sourceID                 END,
      e.valid_until              = CASE row.valid_until              WHEN '' THEN null ELSE row.valid_until              END,
      e.note                     = CASE row.note                     WHEN '' THEN null ELSE row.note                     END,
      e.incorporation_date       = dates[0],
      e.inactivation_date        = dates[1],
      e.struck_off_date          = dates[2],
      e.closed_date              = dates[3]
} IN TRANSACTIONS OF 10000 ROWS;
