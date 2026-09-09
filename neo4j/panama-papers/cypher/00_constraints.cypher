// =============================================================================
// 00 - Constraints  (RUN FIRST, before any data is loaded)
// =============================================================================
// Every node also carries the shared label :Node so that relationships can be
// resolved with a single index seek regardless of the endpoint's concrete type
// (officer_of edges, for example, point at Entity, Officer *and* Intermediary).
//
// Uniqueness constraints are created up front because they back the index used
// by 05_load_relationships.cypher. Secondary indexes are created *after* the
// load instead (06_indexes.cypher) - building them in bulk is much faster.
// =============================================================================

CREATE CONSTRAINT node_id_unique IF NOT EXISTS
FOR (n:Node) REQUIRE n.node_id IS UNIQUE;

CREATE CONSTRAINT entity_id_unique IF NOT EXISTS
FOR (n:Entity) REQUIRE n.node_id IS UNIQUE;

CREATE CONSTRAINT officer_id_unique IF NOT EXISTS
FOR (n:Officer) REQUIRE n.node_id IS UNIQUE;

CREATE CONSTRAINT intermediary_id_unique IF NOT EXISTS
FOR (n:Intermediary) REQUIRE n.node_id IS UNIQUE;

CREATE CONSTRAINT address_id_unique IF NOT EXISTS
FOR (n:Address) REQUIRE n.node_id IS UNIQUE;

CALL db.awaitIndexes();
