// =============================================================================
// 07 - Verification  (expected values are from the raw/ CSV files)
// =============================================================================

// Node counts per label - expect Entity 213,634 | Officer 238,402 |
//                                Intermediary 14,110 | Address 93,454
MATCH (n:Node)
RETURN [l IN labels(n) WHERE l <> 'Node'][0] AS label, count(*) AS nodes
ORDER BY nodes DESC;

// Total nodes - expect 559,600
MATCH (n:Node) RETURN count(n) AS total_nodes;

// Relationship counts - expect OFFICER_OF 309,363 | INTERMEDIARY_OF 213,634
//                              REGISTERED_ADDRESS 151,105  (674,102 total)
MATCH ()-[r]->()
RETURN type(r) AS type, count(*) AS rels
ORDER BY rels DESC;

// Every node must have exactly one concrete label besides :Node - expect 0 rows
MATCH (n:Node) WHERE size(labels(n)) <> 2 RETURN count(n) AS mislabelled;

// Dates must have parsed, not been dropped - expect 213,599 incorporated
MATCH (e:Entity) WHERE e.incorporation_date IS NOT NULL
RETURN count(e)                  AS with_incorporation_date,
       min(e.incorporation_date) AS earliest,
       max(e.incorporation_date) AS latest;

// CSV-corruption tripwire - expect 0.
// Every country_codes value is a 3-letter code, or several joined by ";". A
// backslash mis-parse shifts columns and drops a name or address into this
// property, so anything else here means the CSVs were not staged correctly
// (see stage_csv.sh).
MATCH (n:Node) WHERE n.country_codes IS NOT NULL
  AND NOT n.country_codes =~ '[A-Z]{3}(;[A-Z]{3})*'
RETURN count(n) AS malformed_country_codes;

// Backslash check - expect 0.
// The CSVs in raw/ have had their 15 stray backslashes removed (see README).
// A non-zero count here means an unclean copy of the data was loaded.
MATCH (n:Node)
WHERE (n:Officer AND n.name CONTAINS '\\') OR (n:Address AND n.address CONTAINS '\\')
RETURN count(n) AS rows_with_literal_backslash;

// Spot check: the officer roles carried on OFFICER_OF edges
MATCH ()-[r:OFFICER_OF]->()
RETURN r.link AS role, count(*) AS c ORDER BY c DESC LIMIT 10;

// Sanity walk: an entity with its officers, intermediary and address
MATCH (e:Entity {name: 'TIANSHENG INDUSTRY AND TRADING CO., LTD.'})
OPTIONAL MATCH (e)<-[:OFFICER_OF]-(o:Officer)
OPTIONAL MATCH (e)<-[:INTERMEDIARY_OF]-(i:Intermediary)
OPTIONAL MATCH (e)-[:REGISTERED_ADDRESS]->(a:Address)
RETURN e.name AS entity, e.jurisdiction_description AS jurisdiction,
       collect(DISTINCT o.name) AS officers,
       collect(DISTINCT i.name) AS intermediaries,
       collect(DISTINCT a.address) AS addresses;
