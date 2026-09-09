# Panama Papers → Neo4j

Cypher scripts that load the ICIJ Panama Papers extract in [`raw/`](raw/) into Neo4j,
with the constraints and indexes needed to query it.

## The data

| File | Rows | Becomes |
|---|---:|---|
| `raw/nodes.entity.csv` | 213,634 | `:Entity` — offshore companies, trusts, foundations |
| `raw/nodes.officer.csv` | 238,402 | `:Officer` — shareholders, directors, beneficiaries |
| `raw/nodes.intermediary.csv` | 14,110 | `:Intermediary` — law firms, banks, agents |
| `raw/nodes.address.csv` | 93,454 | `:Address` |
| `raw/edges.csv` | 674,102 | `:OFFICER_OF` (309,363), `:INTERMEDIARY_OF` (213,634), `:REGISTERED_ADDRESS` (151,105) |

559,600 nodes total. Every `node_id` is unique across all four node files and every
edge endpoint resolves — verified against the CSVs before these scripts were written.

## Source and licence

The CSVs in `raw/` are the Panama Papers extract from the
[ICIJ Offshore Leaks Database](https://offshoreleaks.icij.org/), current through
2015. ICIJ publishes the database under the
[Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/),
with its contents under
[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). If you reuse
this data, credit the International Consortium of Investigative Journalists.

ICIJ's own caveat applies and is worth repeating: there are legitimate uses for
offshore companies. The presence of a person or company in this data is **not**
evidence of wrongdoing.

The only change made to the source files here is the removal of 15 stray
backslashes that break CSV parsing — see
[A note on backslashes](#a-note-on-backslashes). Row counts, IDs and every other
value are byte-for-byte as published.

## Graph model

```
(:Officer)      -[:OFFICER_OF       {link, start_date, end_date}]-> (:Entity)
(:Intermediary) -[:INTERMEDIARY_OF  {link, start_date, end_date}]-> (:Entity)
(:Officer)      -[:REGISTERED_ADDRESS]-> (:Address)
(:Entity)       -[:REGISTERED_ADDRESS]-> (:Address)
```

Two modelling decisions worth knowing:

- **Every node also carries a shared `:Node` label.** The edge types are not
  label-homogeneous — a handful of `officer_of` edges point at an `:Officer` or an
  `:Intermediary` rather than an `:Entity`, and `registered_address` starts from both
  officers and entities. The shared label lets the relationship load resolve all
  1.3M endpoints through one index instead of branching per label.
- **Dates become real `date` values.** The CSVs use `dd-MMM-yyyy` (`23-MAR-2006`);
  `incorporation_date`, `inactivation_date`, `struck_off_date`, `start_date` and
  `end_date` are parsed so range queries work. Empty cells are stored as *absent*
  properties rather than empty strings.

`country_codes` / `countries` are kept as the raw source strings so they stay
indexable. Only intermediaries ever hold several `;`-separated codes (704 rows),
so `:Intermediary` additionally gets `country_codes_list` / `countries_list`.

`closed_date` and `company_type` (entities), and `name` and `note` (addresses), are
empty in every row of this extract; the scripts still handle them so a refreshed
dump loads them without edits.

## Staging the CSVs

```bash
NEO4J_HOME=/path/to/neo4j ./cypher/stage_csv.sh   # writes $NEO4J_HOME/import/panama/
```

Neo4j only reads CSV from its own import directory, so the files have to be
copied there before `file:///panama/...` will resolve.

### A note on backslashes

The CSVs in `raw/` have been cleaned of 15 stray backslashes. **The originals on
offshoreleaks.icij.org still contain them**, so this matters if you re-download
the source.

Neo4j reads CSV with `\` as an escape character by default
(`db.import.csv.legacy_quote_escaping=true`). Two of those 15 rows *end* a field
with a backslash, which escapes the field's own closing quote — the parser then
runs past the end of the field and aborts the entire load:

```
nodes.officer.csv:199625   "12201792","WANG LI\","CHN", ...
nodes.address.csv:63038    "14063561","","...JERSEY JE4 8YD\","JEY", ...

Neo.DatabaseError.Statement.ExecutionFailed ... there's a field starting with a
quote and whereas it ends that quote there seems to be characters in that field
after that ending quote. This is what I read: 'WANG LI","CC'
```

The other 13 fail *silently*, which is worse — `c\o Levant Law Practice` loads as
`co Levant Law Practice`, and `THE BEARER \AGENT` as `THE BEARER AGENT`, with no
error at all.

`stage_csv.sh` handles this automatically: it doubles any backslash it finds, so
the value reads back as a literal `\` under that same escaping rule and survives
verbatim. On the cleaned files in `raw/` it finds none and simply copies them.
`07_verify.cypher` asserts the outcome either way.

The alternative is to make Neo4j read strict RFC4180 — set
`db.import.csv.legacy_quote_escaping=false` in `neo4j.conf` and **restart**. That
setting is not dynamic (checked against `GraphDatabaseSettings` in the 5.26.16
jar: it has no `.dynamic()` marker), so it cannot be flipped from Cypher via
`dbms.setConfigValue`.

## Running it

```bash
NEO4J_HOME=/path/to/neo4j NEO4J_PASSWORD=yourpassword ./cypher/load_all.sh
```

This stages the CSVs and then runs each `.cypher` file in order, printing the
verification output. `NEO4J_HOME` locates both `cypher-shell` and the import
directory; override any of `NEO4J_IMPORT`, `NEO4J_URI`, `NEO4J_USER`,
`NEO4J_DATABASE` as needed. Tested against Neo4j 5.26 Enterprise.

To run by hand instead, run `stage_csv.sh` as above and then execute the files in
[`cypher/`](cypher/) in numeric order — in Neo4j Browser or via `cypher-shell -f`.
Expect roughly 3-6 minutes end to end.

| Script | |
|---|---|
| `00_constraints.cypher` | Uniqueness constraints on `node_id`. **Must run first** — the load matches endpoints through them. |
| `01`–`04_load_*.cypher` | One file per node type. |
| `05_load_relationships.cypher` | Reads `edges.csv` once per relationship type (Cypher can't take a type from a variable). |
| `06_indexes.cypher` | Secondary + full-text indexes. **Run after the loads** — bulk building beats maintaining them during import. |
| `07_verify.cypher` | Counts checked against the expected values above. |
| `99_reset.cypher` | Destructive teardown, for re-running a load. |
| `stage_csv.sh` | Copies `raw/` into the import dir, escaping backslashes (see above). |

The load statements use `CALL { … } IN TRANSACTIONS`, which needs an implicit
transaction — hence the `:auto` prefix. Browser and `cypher-shell` both understand
it; if you run these through a driver, strip `:auto` and use an autocommit session.

## Recovering from a partial load

`CALL { … } IN TRANSACTIONS` commits in batches, so a file that fails midway
leaves the rows before the failure committed. Re-running it would hit the
uniqueness constraint, so clear that label first — for example after a failed
`02_load_officers.cypher`:

```cypher
:auto MATCH (o:Officer) CALL { WITH o DETACH DELETE o } IN TRANSACTIONS OF 10000 ROWS;
```

Then re-run the script. `99_reset.cypher` clears everything if you would rather
start over.

## Querying

**New to Cypher or to this dataset? Start with [TUTORIAL.md](TUTORIAL.md)** — 15
progressive scenarios built on the real Aliyev family records in this extract,
following Neo4j's [Panama Papers walkthrough](https://neo4j.com/blog/cypher-and-gql/analyzing-panama-papers-neo4j/)
but rewritten for this graph's model.

```cypher
// Fuzzy name search across entities, officers and intermediaries
CALL db.index.fulltext.queryNodes('node_name', 'poroshenko~') YIELD node, score
RETURN labels(node), node.name, score ORDER BY score DESC LIMIT 20;

// Officers sharing an address with a given company
MATCH (e:Entity {name: 'TIANSHENG INDUSTRY AND TRADING CO., LTD.'})
      -[:REGISTERED_ADDRESS]->(a:Address)<-[:REGISTERED_ADDRESS]-(o:Officer)
RETURN o.name, o.countries, a.address;

// Companies incorporated in the BVI during 2005, with their shareholders
MATCH (o:Officer)-[r:OFFICER_OF]->(e:Entity)
WHERE e.jurisdiction = 'BVI'
  AND e.incorporation_date >= date('2005-01-01')
  AND e.incorporation_date <  date('2006-01-01')
  AND r.link = 'shareholder of'
RETURN e.name, e.status, collect(o.name)[..5] AS shareholders LIMIT 25;
```
