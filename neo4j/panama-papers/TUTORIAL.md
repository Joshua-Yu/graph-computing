# Learning Cypher with the Panama Papers

A progressive tutorial built on the graph loaded by [`cypher/`](cypher/). Each
scenario states an investigative question, the query that answers it, what you
should get back, and the Cypher idea it teaches.

Version: 0.2
Last updated: 2026-09-25


References: 

- Neo4j's
[Analyzing the Panama Papers](https://neo4j.com/blog/cypher-and-gql/analyzing-panama-papers-neo4j/)

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

**Hints:** `count(*)` aggregation, and that a non-aggregating expression in
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

**Hints:** the difference between an indexed exact lookup and a full-text
search. Reach for `db.index.fulltext.queryNodes` instead of
`WHERE n.name CONTAINS '…'` — `CONTAINS` on 238k officers cannot use a range
index and scans every node. Add `~` for fuzzy matching (`'exaltaton~'` still hits).

---

## Part 2 — The Aliyev case


### Scenario 3: Find people by surname — and meet the noise problem

```cypher
MATCH (o:Officer)
WHERE toLower(o.name) CONTAINS 'aliyev'
RETURN o.node_id, o.name, o.countries
ORDER BY o.name;
```

Notice most are irrelevant: `AMIR UALIYEV`,
`Mr. Ernest Galiyev`, `MR. MUHAMMAD MAMADALIYEV`, `YELTINZHAL TURGANALIYEV`.
Substring matching does not respect word boundaries.


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


**Hints:** relationship properties, and reading direction — `OFFICER_OF` always
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

**Hints:** `OPTIONAL MATCH` (a missing address must not delete the whole row)
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

**Hints:** `split`, negative list indexing (`parts[-1]` refers to the last item in the list).

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

Who else sits at an address, given a person:

```cypher
MATCH (start:Officer {name: 'LEYLA ILHAM QIZI ALIYEVA'})
      -[:REGISTERED_ADDRESS]->(a:Address)<-[:REGISTERED_ADDRESS]-(other)
WHERE other <> start
RETURN a.address, [l IN labels(other) WHERE l <> 'Node'][0] AS type, other.name;
```

**Hints:** the two-hop "shared neighbour" pattern `(x)-->(hub)<--(y)`, and `other <> start` to drop the trivial self-match.

---

### Scenario 7: Which people co-own multiple companies?



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

From results, there are `BOS NOMINEES (JERSEY) LIMITED` + `BOS SECRETARIES (JERSEY) LIMITED` sharing 362 
companies. These are corporate service infrastructure appearing on thousands of filings.

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

**Hints:** `o1.node_id < o2.node_id` to emit each unordered pair once to avoid double-counting.

---

### Scenario 8: How are two people connected?

```cypher
MATCH (a:Officer {name: 'Mehriban Aliyeva'}), (b:Officer {name: 'Leyla Aliyeva'})
MATCH p = shortestPath((a)-[*..6]-(b))
RETURN [n IN nodes(p) | coalesce(n.name, n.address)] AS hops, length(p);
```

They meet at UF UNIVERSE FOUNDATION — Mehriban is its *protector*, Leyla a
beneficiary, shareholder and director.

**Hints:** `shortestPath`, undirected and bounded traversal (`-[*..6]-`, no arrow, because a
connection can run either way), and `coalesce` to print whichever name property a
node happens to have. 

To show the results as a graph, return `p` instead od properties: 

```cypher
MATCH (a:Officer {name: 'Mehriban Aliyeva'}), (b:Officer {name: 'Leyla Aliyeva'})
MATCH p = shortestPath((a)-[*..6]-(b))
RETURN p;
```


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


---

### Scenario 12: Nominee officers

```cypher
MATCH (o:Officer)-[:OFFICER_OF]->(e:Entity)
RETURN o.name, count(e) AS companies
ORDER BY companies DESC LIMIT 10;
```

`MOSSFON SUBSCRIBERS LTD.` holds positions in **3,958** companies — a Mossack
Fonseca in-house nominee. Real individuals essentially never exceed a few dozen,
so this is a useful filter to exclude elsewhere.

---

### Scenario 13: Incorporations over time

Because the loader parsed `dd-MMM-yyyy` into real `date` values, temporal queries
work directly:

```cypher
MATCH (e:Entity) WHERE e.incorporation_date IS NOT NULL
WITH e, toInteger(split(e.incorporation_date, '-')[-1]) AS year
RETURN year, count(e) as count
ORDER BY year ASC;
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

**Hints:** date component access (`.year`), half-open date ranges — safer than
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

**Hints:** `MERGE` for idempotent writes (re-running creates nothing new — unlike
 `CREATE`, which duplicates on a second run).

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

Show the graph: 
```cypher
MATCH path = (p:Person)<-[:IDENTITY]-(o:Officer)-[r:OFFICER_OF]->(e:Entity)
RETURN path LIMIT 20;
```


