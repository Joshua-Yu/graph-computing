# Learning Cypher with the Panama Papers

A progressive tutorial built on the graph loaded by [`cypher/`](cypher/). Each
scenario states an investigative question, the query that answers it, what you
should get back, and the Cypher idea it teaches.

The scenarios follow the investigation in Neo4j's
[Analyzing the Panama Papers](https://neo4j.com/blog/cypher-and-gql/analyzing-panama-papers-neo4j/),
but every query here is rewritten for the **real ICIJ dump in `raw/`** rather than
the small hand-built sample in that post. The model differs accordingly:

| Blog post sample | This dataset |
|---|---|
| `:Company` | `:Entity` |
| `:Client` + `REGISTERED` | `:Intermediary` + `INTERMEDIARY_OF` |
| `IOO_SHAREHOLDER`, `IOO_BENEFICIARY`, `IOO_PROTECTOR`, `IOO_BSD` | one `:OFFICER_OF` type, with the role in `r.link` |
| `HAS_SIMILIAR_NAME`, `:Person`, `IDENTITY` | not in the source — you derive them in Part 4 |

Run these one at a time in Neo4j Browser. Expected counts are from this extract,
so you can check your own results as you go.

---

## Part 1 — Getting oriented

### Scenario 1: What is actually in this graph?

Before investigating anything, learn the shape of the data.

```cypher
MATCH (n:Node)
RETURN [l IN labels(n) WHERE l <> 'Node'][0] AS label, count(*) AS nodes
ORDER BY nodes DESC;
```

Expect `Officer 238,402`, `Entity 213,634`, `Address 93,454`, `Intermediary 14,110`.

```cypher
MATCH ()-[r]->() RETURN type(r) AS relationship, count(*) AS rels ORDER BY rels DESC;
```

Expect `OFFICER_OF 309,363`, `INTERMEDIARY_OF 213,634`, `REGISTERED_ADDRESS 151,105`.

**Teaches:** `count(*)` aggregation, and that a non-aggregating expression in
`RETURN` becomes the grouping key. Every node carries the shared `:Node` label,
which is why one query can count all four types.

---

### Scenario 2: Two ways to find a company, and why one is much better

Exact match, which uses the range index on `:Entity(name)`:

```cypher
MATCH (e:Entity {name: 'Exaltation Limited'})
RETURN e.name, e.jurisdiction_description, e.status, e.incorporation_date;
```

Expect one row: British Virgin Islands, Active, incorporated 2015-01-02.

Now a fuzzy search using the full-text index, which handles spelling and case:

```cypher
CALL db.index.fulltext.queryNodes('node_name', 'exaltation') YIELD node, score
RETURN [l IN labels(node) WHERE l <> 'Node'][0] AS type, node.name, score
ORDER BY score DESC LIMIT 10;
```

**Teaches:** the difference between an indexed exact lookup and a full-text
search. Reach for `db.index.fulltext.queryNodes` instead of
`WHERE n.name CONTAINS '…'` — `CONTAINS` on 238k officers cannot use a range
index and scans every node. Add `~` for fuzzy matching (`'exaltaton~'` still hits).

---

## Part 2 — The Aliyev case

This is the investigation from the blog post, reproduced against the real data.

### Scenario 3: Find people by surname — and meet the noise problem

```cypher
MATCH (o:Officer)
WHERE toLower(o.name) CONTAINS 'aliyev'
RETURN o.node_id, o.name, o.countries
ORDER BY o.name;
```

Expect **28 rows** — and notice most are irrelevant: `AMIR UALIYEV`,
`Mr. Ernest Galiyev`, `MR. MUHAMMAD MAMADALIYEV`, `YELTINZHAL TURGANALIYEV`.
Substring matching does not respect word boundaries.

**Teaches:** why naive substring search is a poor first filter, and the habit of
looking at what a query *wrongly* includes, not just what it finds.

---

### Scenario 4: Everyone attached to one company

```cypher
MATCH (o:Officer)-[r:OFFICER_OF]->(e:Entity {name: 'Exaltation Limited'})
RETURN o.name AS officer, r.link AS role
ORDER BY role, officer;
```

Six rows for what are really **two people**:

| officer | role |
|---|---|
| Arzu Ilham Qizi Aliyeva | beneficiary of |
| Leyla Ilham Qizi Aliyeva | beneficiary of |
| Arzu Aliyeva | beneficiary, shareholder and director of |
| Leyla Aliyeva | beneficiary, shareholder and director of |
| ARZU ILHAM QIZI ALIYEVA | shareholder of |
| LEYLA ILHAM QIZI ALIYEVA | shareholder of |

The blog post models these roles as separate relationship types (`IOO_SHAREHOLDER`,
`IOO_BENEFICIARY`). In the real data there is **one** `OFFICER_OF` type and the
role lives in `r.link`, so you filter on a property instead of a type:

```cypher
MATCH (o:Officer)-[r:OFFICER_OF]->(e:Entity)
WHERE r.link = 'shareholder of' AND e.name = 'Exaltation Limited'
RETURN o.name;
```

**Teaches:** relationship properties, and reading direction — `OFFICER_OF` always
points *from* the officer *to* the entity.

Widen it to the whole company profile:

```cypher
MATCH (e:Entity {name: 'Exaltation Limited'})
OPTIONAL MATCH (e)<-[r:OFFICER_OF]-(o:Officer)
OPTIONAL MATCH (e)<-[:INTERMEDIARY_OF]-(i:Intermediary)
OPTIONAL MATCH (e)-[:REGISTERED_ADDRESS]->(a:Address)
RETURN e.name, e.jurisdiction_description,
       collect(DISTINCT o.name + ' (' + r.link + ')') AS officers,
       collect(DISTINCT i.name) AS intermediaries,
       collect(DISTINCT a.address) AS addresses;
```

The intermediary is **CHILD & CHILD**, a London law firm.

**Teaches:** `OPTIONAL MATCH` (a missing address must not delete the whole row)
and `collect(DISTINCT …)` to fold many rows into one.

---

### Scenario 5: The same person, spelled four ways

The core data-quality problem of this dataset. Group officers by a normalised
first + last name:

```cypher
MATCH (o:Officer)
WHERE toLower(o.name) CONTAINS 'aliyev'
WITH split(toLower(trim(o.name)), ' ') AS parts, o
WITH parts[0] + ' ' + parts[-1] AS normalised, collect(o.name) AS variants, count(*) AS n
WHERE n > 1
RETURN normalised, variants, n ORDER BY n DESC;
```

`leyla aliyeva` and `arzu aliyeva` each collapse three records into one person.

Now run it across the entire dataset — and read the result critically:

```cypher
MATCH (o:Officer) WHERE o.name IS NOT NULL
WITH split(toLower(trim(o.name)), ' ') AS parts, o
WITH parts[0] + ' ' + parts[-1] AS normalised, collect(o.name) AS names, count(*) AS n
WHERE n > 1
RETURN normalised, names[..5] AS sample, n ORDER BY n DESC LIMIT 10;
```

The top result is **`the bearer` with 71,420 records**, followed by
`el portador` (9,351, Spanish for the same thing). These are *bearer shares* —
ownership belongs to whoever physically holds the certificate — not a person named
Bearer. There are 22,020 duplicate groups in total, and the head of that list is
almost entirely placeholders and nominee firms.

**Teaches:** `split`, negative list indexing (`parts[-1]`), `collect` with a slice
(`[..5]`), and the analytical lesson that the biggest cluster in a real dataset is
usually an artefact. Always exclude placeholders before drawing conclusions:

```cypher
… WHERE n > 1 AND NOT normalised IN ['the bearer', 'el portador', 'bearer'] …
```

---

### Scenario 6: A shared address as evidence of identity

The four `Ilham Qizi` records are separate nodes. Are they the same people?

```cypher
MATCH (o:Officer)-[:REGISTERED_ADDRESS]->(a:Address)
WHERE toLower(o.name) CONTAINS 'ilham qizi'
RETURN a.address, a.countries, collect(o.name) AS officers, count(*) AS n;
```

All four share **`7 S. Vurgun Street; Baku AZ1 001; Azerbaijan`**. Different
spellings, one household.

Turn that into a general technique — who else sits at an address, given a person:

```cypher
MATCH (start:Officer {name: 'LEYLA ILHAM QIZI ALIYEVA'})
      -[:REGISTERED_ADDRESS]->(a:Address)<-[:REGISTERED_ADDRESS]-(other)
WHERE other <> start
RETURN a.address, [l IN labels(other) WHERE l <> 'Node'][0] AS type, other.name;
```

**Teaches:** the two-hop "shared neighbour" pattern `(x)-->(hub)<--(y)`, the
workhorse of link analysis, and `other <> start` to drop the trivial self-match.

---

### Scenario 7: Which people co-own multiple companies?

The blog's co-occurrence query. Run naively this is dangerous: one company here has
1,006 officers, which alone generates ~506,000 pairs. Bound it first.

```cypher
MATCH (e:Entity)<-[:OFFICER_OF]-(o:Officer)
WITH e, collect(o) AS officers
WHERE size(officers) <= 50                     // skip mass-nominee vehicles
UNWIND officers AS o1
UNWIND officers AS o2
WITH e, o1, o2 WHERE o1.node_id < o2.node_id   // each pair once, never mirrored
WITH o1.name AS first, o2.name AS second,
     count(*) AS shared, collect(e.name) AS companies
WHERE shared > 1
RETURN first, second, shared, companies
ORDER BY shared DESC LIMIT 20;
```

9,233 pairs qualify. The top of the list is *not* a family — it is
`BOS NOMINEES (JERSEY) LIMITED` + `BOS SECRETARIES (JERSEY) LIMITED` sharing 318
companies, then `TENBY NOMINEES` + `BROCK NOMINEES` with 186. These are corporate
service infrastructure appearing on thousands of filings.

Scope it to the family and the signal appears:

```cypher
MATCH (o1:Officer)-[:OFFICER_OF]->(e:Entity)<-[:OFFICER_OF]-(o2:Officer)
WHERE o1.node_id < o2.node_id
  AND toLower(o1.name) CONTAINS 'aliyev' AND toLower(o2.name) CONTAINS 'aliyev'
WITH o1.name AS first, o2.name AS second, collect(e.name) AS companies
RETURN first, second, size(companies) AS shared, companies ORDER BY shared DESC;
```

`Leyla Aliyeva` and `Arzu Aliyeva` share **three**: Exaltation Limited,
KINGSVIEW DEVELOPMENTS LIMITED, and UF UNIVERSE FOUNDATION.

**Teaches:** `o1.node_id < o2.node_id` to emit each unordered pair once, why
`UNWIND` of a collected list beats a self-join, and — most importantly — that
degree hubs dominate co-occurrence rankings unless you filter them out.

---

### Scenario 8: How are two people connected?

```cypher
MATCH (a:Officer {name: 'Mehriban Aliyeva'}), (b:Officer {name: 'Leyla Aliyeva'})
MATCH p = shortestPath((a)-[*..6]-(b))
RETURN [n IN nodes(p) | coalesce(n.name, n.address)] AS hops, length(p);
```

They meet at UF UNIVERSE FOUNDATION — Mehriban is its *protector*, Leyla a
beneficiary, shareholder and director.

**Teaches:** `shortestPath`, undirected traversal (`-[*..6]-`, no arrow, because a
connection can run either way), and `coalesce` to print whichever name property a
node happens to have. **Always bound the hop count** — an unbounded `[*]` on a
graph with 1,000-officer hubs will not come back.

---

## Part 3 — Whole-dataset analysis

### Scenario 9: Who are the biggest intermediaries?

```cypher
MATCH (i:Intermediary)-[:INTERMEDIARY_OF]->(e:Entity)
RETURN i.name, i.countries, count(e) AS clients
ORDER BY clients DESC LIMIT 10;
```

Expect `ORION HOUSE SERVICES (HK) LIMITED` 7,016, then `MOSSACK FONSECA & CO.`
4,364, `PRIME CORPORATE SOLUTIONS SARL` 4,117.

Note the blog's `Mossack Fonseca & Co (UK)` is really
`MOSSACK FONSECA & CO. (U.K.) LTD.` here — the firm appears under dozens of
country-specific records, another entity-resolution trap.

---

### Scenario 10: Where are these companies registered?

```cypher
MATCH (e:Entity)
RETURN e.jurisdiction_description AS jurisdiction, count(*) AS companies
ORDER BY companies DESC LIMIT 10;
```

British Virgin Islands 113,648 — more than half the dataset — then Panama 48,360,
Bahamas 15,915, Seychelles 15,182.

---

### Scenario 11: Mass registration addresses

```cypher
MATCH (a:Address)<-[:REGISTERED_ADDRESS]-(n)
RETURN a.address, a.countries, count(*) AS registered
ORDER BY registered DESC LIMIT 10;
```

The top four results are all the **same building** in Road Town, Tortola, entered
four different ways (`AKARA BLDG.; 24 DE CASTRO STREET…`, `Akara Building; 24 de
Castro Street…`, …) with 1,007 + 813 + 686 + 667 registrations.

**Teaches:** hub detection, and that entity resolution applies to addresses just as
much as to people. The true concentration is roughly triple what any single row
suggests.

---

### Scenario 12: Nominee officers

```cypher
MATCH (o:Officer)-[:OFFICER_OF]->(e:Entity)
RETURN o.name, count(e) AS companies
ORDER BY companies DESC LIMIT 10;
```

`MOSSFON SUBSCRIBERS LTD.` holds positions in **3,882** companies — a Mossack
Fonseca in-house nominee. Real individuals essentially never exceed a few dozen,
so this is a useful filter to exclude elsewhere.

---

### Scenario 13: Incorporations over time

Because the loader parsed `dd-MMM-yyyy` into real `date` values, temporal queries
work directly:

```cypher
MATCH (e:Entity) WHERE e.incorporation_date IS NOT NULL
RETURN e.incorporation_date.year AS year, count(*) AS incorporations
ORDER BY year;
```

The range runs 1936–2015 and peaks in 2005 (13,246), 2007 (12,814) and 2006 (12,355).

Combine time with structure — BVI shell companies incorporated in 2005 that are
still active:

```cypher
MATCH (o:Officer)-[r:OFFICER_OF]->(e:Entity)
WHERE e.jurisdiction = 'BVI' AND e.status = 'Active'
  AND e.incorporation_date >= date('2005-01-01')
  AND e.incorporation_date <  date('2006-01-01')
  AND r.link = 'shareholder of'
WITH e, collect(o.name) AS shareholders
RETURN e.name, e.incorporation_date, shareholders[..5] AS shareholders
LIMIT 25;
```

**Teaches:** date component access (`.year`), half-open date ranges — safer than
`BETWEEN`-style logic — and combining property filters with graph patterns.

---

## Part 4 — Enriching the graph

The source has no notion that four officer records are two people. You add it.
**These queries write to the graph**; the cleanup is at the end.

### Scenario 14: Collapse duplicates into `:Person` nodes

```cypher
MATCH (o:Officer) WHERE toLower(o.name) CONTAINS 'aliyev'
WITH split(toLower(trim(o.name)), ' ') AS parts, o
WITH parts[0] + ' ' + parts[-1] AS name, collect(o) AS officers
WHERE size(officers) > 1
MERGE (p:Person {name: name})
WITH p, officers
UNWIND officers AS o
MERGE (o)-[:IDENTITY]->(p)
RETURN p.name, count(*) AS merged_records;
```

**Teaches:** `MERGE` for idempotent writes (re-running creates nothing new — unlike
the blog's `CREATE`, which duplicates on a second run), and `UNWIND` to turn a
collected list back into rows.

### Scenario 15: Query through the resolved layer

```cypher
MATCH (p:Person)<-[:IDENTITY]-(o:Officer)-[r:OFFICER_OF]->(e:Entity)
RETURN p.name AS person,
       count(DISTINCT e) AS companies,
       collect(DISTINCT e.name) AS company_names,
       collect(DISTINCT r.link) AS roles;
```

Each person now shows a single consolidated holding across all their spellings —
the result the raw data could not give you.

### Cleanup

```cypher
MATCH (p:Person) DETACH DELETE p;
```

---

## Part 5 — Making queries fast

Put `PROFILE` in front of any query to see the plan and the rows touched at each
step. Compare these two:

```cypher
PROFILE MATCH (e:Entity {name: 'Exaltation Limited'}) RETURN e;
PROFILE MATCH (e:Entity) WHERE e.name CONTAINS 'Exaltation' RETURN e;
```

The first shows `NodeIndexSeek` and touches a handful of rows; the second shows
`NodeByLabelScan` and touches all 213,634. That difference is the whole reason for
[`cypher/06_indexes.cypher`](cypher/06_indexes.cypher).

Three rules that matter on this dataset:

1. **Bound variable-length paths.** `-[*..6]-` is fine; `-[*]-` will hang on hubs
   like ACCELONIC LTD (1,006 officers).
2. **Filter hubs out of pair and path analysis.** Nominee companies and shared
   registered-agent addresses connect almost everything to everything.
3. **Aggregate before expanding.** `WITH e, collect(o) AS officers WHERE size(officers) <= 50`
   discards the explosive cases before the cross-product, not after.
