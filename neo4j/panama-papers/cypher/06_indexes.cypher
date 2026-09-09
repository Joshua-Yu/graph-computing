// =============================================================================
// 06 - Secondary indexes  (RUN AFTER the data is loaded)
// =============================================================================
// Uniqueness constraints on node_id already exist from 00_constraints.cypher.
// Everything here supports querying rather than loading, so it is built in bulk
// afterwards - considerably faster than maintaining it row by row during import.
// =============================================================================

// --- Name lookups (exact match and STARTS WITH) ------------------------------
CREATE INDEX entity_name IF NOT EXISTS       FOR (n:Entity)       ON (n.name);
CREATE INDEX officer_name IF NOT EXISTS      FOR (n:Officer)      ON (n.name);
CREATE INDEX intermediary_name IF NOT EXISTS FOR (n:Intermediary) ON (n.name);

// --- Geography ---------------------------------------------------------------
// Stored as the raw source string. Intermediaries may hold several ";"-separated
// codes, for which `country_codes_list` is available (see 03_load_...cypher).
CREATE INDEX entity_country IF NOT EXISTS       FOR (n:Entity)       ON (n.country_codes);
CREATE INDEX officer_country IF NOT EXISTS      FOR (n:Officer)      ON (n.country_codes);
CREATE INDEX intermediary_country IF NOT EXISTS FOR (n:Intermediary) ON (n.country_codes);
CREATE INDEX address_country IF NOT EXISTS      FOR (n:Address)      ON (n.country_codes);

// --- Entity attributes used for filtering and ranges -------------------------
CREATE INDEX entity_jurisdiction IF NOT EXISTS FOR (n:Entity) ON (n.jurisdiction);
CREATE INDEX entity_status IF NOT EXISTS       FOR (n:Entity) ON (n.status);
CREATE INDEX entity_incorporated IF NOT EXISTS FOR (n:Entity) ON (n.incorporation_date);
CREATE INDEX entity_ibcruc IF NOT EXISTS       FOR (n:Entity) ON (n.ibcRUC);

// --- Role filtering on officer edges ("shareholder of", "director of", ...) --
CREATE INDEX officer_of_link IF NOT EXISTS FOR ()-[r:OFFICER_OF]-() ON (r.link);

// --- Free-text search --------------------------------------------------------
// Use with: CALL db.index.fulltext.queryNodes('node_name', 'putin~') YIELD node, score
CREATE FULLTEXT INDEX node_name IF NOT EXISTS
FOR (n:Entity|Officer|Intermediary) ON EACH [n.name];

CREATE FULLTEXT INDEX address_text IF NOT EXISTS
FOR (n:Address) ON EACH [n.address];

CALL db.awaitIndexes();
