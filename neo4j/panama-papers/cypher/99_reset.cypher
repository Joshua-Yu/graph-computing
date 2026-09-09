// =============================================================================
// 99 - Reset  (DESTRUCTIVE - deletes every node, relationship, index and
//              constraint in the current database. Only for re-running a load.)
// =============================================================================

:auto MATCH (n) CALL { WITH n DETACH DELETE n } IN TRANSACTIONS OF 10000 ROWS;

DROP INDEX node_name IF EXISTS;
DROP INDEX address_text IF EXISTS;
DROP INDEX entity_name IF EXISTS;
DROP INDEX officer_name IF EXISTS;
DROP INDEX intermediary_name IF EXISTS;
DROP INDEX entity_country IF EXISTS;
DROP INDEX officer_country IF EXISTS;
DROP INDEX intermediary_country IF EXISTS;
DROP INDEX address_country IF EXISTS;
DROP INDEX entity_jurisdiction IF EXISTS;
DROP INDEX entity_status IF EXISTS;
DROP INDEX entity_incorporated IF EXISTS;
DROP INDEX entity_ibcruc IF EXISTS;
DROP INDEX officer_of_link IF EXISTS;

DROP CONSTRAINT node_id_unique IF EXISTS;
DROP CONSTRAINT entity_id_unique IF EXISTS;
DROP CONSTRAINT officer_id_unique IF EXISTS;
DROP CONSTRAINT intermediary_id_unique IF EXISTS;
DROP CONSTRAINT address_id_unique IF EXISTS;
