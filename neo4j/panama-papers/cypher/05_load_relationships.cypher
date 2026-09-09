// =============================================================================
// 05 - Relationships                                        674,102 rows
// =============================================================================
// Source: raw/edges.csv
//
// Cypher cannot take a relationship type from a variable, so the file is read
// once per TYPE value. Endpoints are matched on the shared :Node label because
// the edge types are not label-homogeneous:
//
//   officer_of          309,363   Officer -> Entity | Officer | Intermediary
//   intermediary_of     213,634   Intermediary -> Entity
//   registered_address  151,105   Officer | Entity -> Address
//
// The `link` property carries the fine-grained role ("shareholder of",
// "beneficiary of", "director of", ...); on the other two types it is constant.
// Requires 00_constraints.cypher to have run - the :Node(node_id) index is what
// makes these 1.3M endpoint lookups fast.
// =============================================================================

// --- officer_of --------------------------------------------------------------
:auto LOAD CSV WITH HEADERS FROM 'file:///panama/edges.csv' AS row
WITH row WHERE row.TYPE = 'officer_of'
CALL {
  WITH row
  WITH row, {JAN:'01', FEB:'02', MAR:'03', APR:'04', MAY:'05', JUN:'06',
             JUL:'07', AUG:'08', SEP:'09', OCT:'10', NOV:'11', DEC:'12'} AS mm
  WITH row,
       [d IN [row.start_date, row.end_date] |
          CASE WHEN d IS NULL OR d = '' THEN null
               ELSE date(right(d, 4) + '-' + mm[substring(d, 3, 3)] + '-' + left(d, 2))
          END] AS dates
  MATCH (s:Node {node_id: toInteger(row.START_ID)})
  MATCH (t:Node {node_id: toInteger(row.END_ID)})
  CREATE (s)-[r:OFFICER_OF]->(t)
  SET r.link        = CASE row.link        WHEN '' THEN null ELSE row.link        END,
      r.sourceID    = CASE row.sourceID    WHEN '' THEN null ELSE row.sourceID    END,
      r.valid_until = CASE row.valid_until WHEN '' THEN null ELSE row.valid_until END,
      r.start_date  = dates[0],
      r.end_date    = dates[1]
} IN TRANSACTIONS OF 10000 ROWS;

// --- intermediary_of ---------------------------------------------------------
:auto LOAD CSV WITH HEADERS FROM 'file:///panama/edges.csv' AS row
WITH row WHERE row.TYPE = 'intermediary_of'
CALL {
  WITH row
  WITH row, {JAN:'01', FEB:'02', MAR:'03', APR:'04', MAY:'05', JUN:'06',
             JUL:'07', AUG:'08', SEP:'09', OCT:'10', NOV:'11', DEC:'12'} AS mm
  WITH row,
       [d IN [row.start_date, row.end_date] |
          CASE WHEN d IS NULL OR d = '' THEN null
               ELSE date(right(d, 4) + '-' + mm[substring(d, 3, 3)] + '-' + left(d, 2))
          END] AS dates
  MATCH (s:Node {node_id: toInteger(row.START_ID)})
  MATCH (t:Node {node_id: toInteger(row.END_ID)})
  CREATE (s)-[r:INTERMEDIARY_OF]->(t)
  SET r.link        = CASE row.link        WHEN '' THEN null ELSE row.link        END,
      r.sourceID    = CASE row.sourceID    WHEN '' THEN null ELSE row.sourceID    END,
      r.valid_until = CASE row.valid_until WHEN '' THEN null ELSE row.valid_until END,
      r.start_date  = dates[0],
      r.end_date    = dates[1]
} IN TRANSACTIONS OF 10000 ROWS;

// --- registered_address ------------------------------------------------------
:auto LOAD CSV WITH HEADERS FROM 'file:///panama/edges.csv' AS row
WITH row WHERE row.TYPE = 'registered_address'
CALL {
  WITH row
  WITH row, {JAN:'01', FEB:'02', MAR:'03', APR:'04', MAY:'05', JUN:'06',
             JUL:'07', AUG:'08', SEP:'09', OCT:'10', NOV:'11', DEC:'12'} AS mm
  WITH row,
       [d IN [row.start_date, row.end_date] |
          CASE WHEN d IS NULL OR d = '' THEN null
               ELSE date(right(d, 4) + '-' + mm[substring(d, 3, 3)] + '-' + left(d, 2))
          END] AS dates
  MATCH (s:Node {node_id: toInteger(row.START_ID)})
  MATCH (t:Node {node_id: toInteger(row.END_ID)})
  CREATE (s)-[r:REGISTERED_ADDRESS]->(t)
  SET r.link        = CASE row.link        WHEN '' THEN null ELSE row.link        END,
      r.sourceID    = CASE row.sourceID    WHEN '' THEN null ELSE row.sourceID    END,
      r.valid_until = CASE row.valid_until WHEN '' THEN null ELSE row.valid_until END,
      r.start_date  = dates[0],
      r.end_date    = dates[1]
} IN TRANSACTIONS OF 10000 ROWS;
