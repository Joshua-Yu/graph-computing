# Panama Papers Graph Demo: 40-Minute Walkthrough

Oct 8, 2026 · @Joshua Yu

## At a glance

The session answers one investigative question live, "how are these two people connected?", and uses it to teach the graph model to people who think in tables. Every query runs against the Panama Papers graph already loaded from this repo: 559,600 nodes and 674,102 relationships.

**Audience:** fluent in SQL, joins, foreign keys, indexes and normalisation. No graph experience assumed.

**Format:** live querying in Neo4j Browser, 14 queries, two whiteboard moments, no slides required.

**The three ideas the room should leave with:**

1. **Relationships are stored, not computed.** A join is worked out at query time from matching key values. A relationship is a record written once, at insert time, that both of its nodes point to.
2. **A Cypher query is a drawing of the shape you want.** `(officer)-[:OFFICER_OF]->(entity)` is the query. You describe the pattern and the database finds every place it occurs.
3. **Depth is cheap.** "Any connection up to six hops away" is one line of Cypher. Its cost follows the neighbourhood you touch, not the size of the tables.

**The thread that ties it together:** each segment translates one thing the room already knows (a row, a foreign key, a join table, a recursive CTE) into its graph equivalent.

## Run of show

Five teaching segments and a three-minute close. Each segment starts from something the room already does in SQL.

| Time | Segment | What they already know | The graph idea | Queries |
| --- | --- | --- | --- | --- |
| 0:00 to 0:05 | 1. The hook | Recursive CTEs, and how they feel | A path is something you can ask for directly | 1 |
| 0:05 to 0:12 | 2. The property graph model | Rows, columns, foreign keys, join tables | Nodes, labels, properties, relationships | 2 to 4 |
| 0:12 to 0:22 | 3. Pattern matching in Cypher | SELECT, JOIN, LEFT JOIN, self-join | MATCH, patterns, OPTIONAL MATCH | 5 to 8 |
| 0:22 to 0:32 | 4. Traversals | Join chains of fixed length, recursion | Fixed chains, variable length, shortest path | 9 to 12 |
| 0:32 to 0:37 | 5. Core concepts | Query plans, indexes, ALTER TABLE | Index-free adjacency, anchor indexes, optional schema | 13 to 14 |
| 0:37 to 0:40 | Wrap-up and questions |  |  |  |

**If you run late:** cut Query 14 first (saves 2 minutes), then Query 6 (saves 2 minutes). Never cut Query 10 or 12; they carry the session.

**Pacing rule:** type the short queries live, paste the long ones. Typing `(o)-[:OFFICER_OF]->(e)` in front of the room is the lesson.

## Before you start

Dry-run all 14 queries once on the demo machine. The expected results below were checked against the CSVs in `raw/` or taken from `TUTORIAL.md`, but none of the queries was executed against the live database while drafting this.

**The data.** The ICIJ Panama Papers extract, loaded by `cypher/load_all.sh` into Neo4j 5.26: 213,634 entities, 238,402 officers, 14,110 intermediaries, 93,454 addresses.

**Checklist**

- [ ] Run `cypher/07_verify.cypher` and confirm the counts match the README.
- [ ] Confirm there are no leftover enrichment nodes: `MATCH (p:Person) RETURN count(p);` should return 0.
- [ ] Run every query once so the page cache is warm and nothing is slow the first time.
- [ ] Save the 14 queries as Browser favourites, numbered, in order.
- [ ] In Neo4j Browser, set node captions to `name` for Officer, Entity and Intermediary, and to `address` for Address.
- [ ] Raise the editor and result font size; check it from the back of the room.
- [ ] Have a whiteboard or a blank slide ready for the model drawing in Segment 2.
- [ ] Keep `raw/edges.csv` open in a text editor for the hook.

**Say this once, early.** ICIJ's own caveat: there are legitimate uses for offshore companies, and appearing in this data is not evidence of wrongdoing. The demo uses names only as they appear in the published records.

**Do not use `CALL db.schema.visualization()` for the model.** Every node carries a shared `:Node` label, so the generated picture shows a fifth bubble and duplicate arrows. Draw the model by hand instead.

## Segment 1 (0:00 to 0:05): The hook

Make the room feel the cost of a connection question in SQL, then answer it in three lines. Do not explain any syntax yet.

**1. Start in their world (1 min).** Show `raw/edges.csv` in a text editor.

> "This dataset arrives relational. Four node tables, and one edge table with `START_ID`, `TYPE`, `END_ID`. You could have it in Postgres in ten minutes."

**2. Pose the question (1 min).**

> "Two names in these records: Mehriban Aliyeva and Leyla Aliyeva. Are they connected, and through what? It could be a shared company, a shared address, a shared law firm, or a chain of those. We do not know the route in advance. That is the whole problem."

**3. Show the SQL, do not run it (1.5 min).**

```sql
WITH RECURSIVE walk (node_id, depth, path) AS (
    SELECT o.node_id, 0, ARRAY[o.node_id]
    FROM   officer o
    WHERE  o.name = 'Mehriban Aliyeva'
  UNION ALL
    SELECT nxt.id, w.depth + 1, w.path || nxt.id
    FROM   walk w
    JOIN   edges x ON w.node_id IN (x.start_id, x.end_id)
    CROSS  JOIN LATERAL (
             SELECT CASE WHEN x.start_id = w.node_id
                         THEN x.end_id ELSE x.start_id END AS id
           ) nxt
    WHERE  w.depth < 6
      AND  nxt.id <> ALL (w.path)
)
SELECT w.path, w.depth
FROM   walk w
JOIN   officer t ON t.node_id = w.node_id
WHERE  t.name = 'Leyla Aliyeva'
ORDER  BY w.depth
LIMIT  1;
```

Point at three things:

- It returns an array of ids. Names need four more joins, one per node table.
- It walks every route out to depth 6 before it picks the shortest. There is no early exit.
- Each step is a lookup into a 674,102-row edge table.

**4. Run Query 1 (1.5 min).**

```cypher
// Query 1
MATCH (a:Officer {name: 'Mehriban Aliyeva'}), (b:Officer {name: 'Leyla Aliyeva'})
MATCH p = shortestPath((a)-[*..6]-(b))
RETURN p;
```

**Expect:** three nodes and two relationships. Both officers point at the entity UF UNIVERSE FOUNDATION. Click each relationship: one is `protector of`, the other `beneficiary, shareholder and director of`.

> "Three lines, and the answer came back as a picture. We will spend the next half hour earning this query, one piece at a time."

**Stay fair.** A relational database can answer this question. The contrast is how much of the route you must spell out, and what the engine does at each hop. An audience of database people will trust the rest of the session more if you say so.

## Segment 2 (0:05 to 0:12): The property graph model

A property graph has four building blocks, and each one maps to something relational. Draw the model on the whiteboard first, then prove each block with a query.

**1. Draw the model (2 min).** Draw circles and arrows, not boxes and crow's feet. Say the names aloud as sentences: "an officer is an officer of an entity".

&#91;embedded content: Panama Papers graph model · 4 node labels, 3 relationship types\]

Entity sits in the middle. Officers and intermediaries both point at it, and officers and entities both point at addresses.

**2. Translate the vocabulary (1 min).** Write this beside the drawing and leave it up for the whole session.

| Relational | Property graph | What actually changes |
| --- | --- | --- |
| Row | Node | A node is a thing with identity, not a tuple in a set |
| Table | Label | A node can carry several labels at once |
| Column | Property | Stored per node; a missing value is an absent property, not a NULL |
| Foreign key, or a join table row | Relationship | It has a type, a direction and its own properties |
| Join | Following a relationship | The connection is written at insert time, not matched at query time |

**3. Query 2: what is in here (1 min).**

```cypher
// Query 2
MATCH (n)
RETURN labels(n) AS labels, count(*) AS nodes
ORDER BY nodes DESC;
```

**Expect:** four rows, each with two labels: Officer 238,402, Entity 213,634, Address 93,454, Intermediary 14,110.

> "Two things to notice. Every node has two labels, its own type and a shared `Node`. And there is no GROUP BY: whatever you do not aggregate becomes the grouping key."

**4. Query 3: one node (1.5 min).** Type this one live.

```cypher
// Query 3
MATCH (e:Entity {name: 'Exaltation Limited'})
RETURN e;
```

**Expect:** one node. Click it: British Virgin Islands, status Active, incorporated 2015-01-02.

> "Round brackets are a node, because they look like a circle. The colon is the label. The curly braces are a filter, the same as a WHERE clause."

Point at what is missing from the property list: there is no `closed_date`. The source cell was empty, so the property does not exist on this node.

**5. Query 4: one relationship (1.5 min).**

```cypher
// Query 4
MATCH (o:Officer)-[r:OFFICER_OF]->(e:Entity {name: 'Exaltation Limited'})
RETURN o, r, e;
```

**Expect:** six officers around one entity. Click a relationship to show its `link` property, for example `shareholder of`.

> "Square brackets are a relationship, and the arrow is its direction. In SQL this would be a join table with a role column. Here that join row is a first-class object with its own type and its own data."

**Plant a seed.** The six officers are visibly two people, each spelled three ways. Say "hold that thought" and move on. Query 14 pays it off.

## Segment 3 (0:12 to 0:22): Pattern matching in Cypher

`MATCH` is `FROM` and `JOIN` in one clause: you draw a shape, and every place that shape occurs in the graph becomes a row. Four queries, each adding one idea.

**1. Query 5: the same pattern as a table (2 min).**

```cypher
// Query 5
MATCH (o:Officer)-[r:OFFICER_OF]->(e:Entity {name: 'Exaltation Limited'})
WHERE r.link CONTAINS 'shareholder'
RETURN o.name AS officer, r.link AS role
ORDER BY role, officer;
```

**Expect:** four rows. Arzu Aliyeva and Leyla Aliyeva as `beneficiary, shareholder and director of`; the two upper-case ILHAM QIZI records as `shareholder of`.

Put the SQL next to it:

```sql
SELECT o.name, x.link
FROM   officer o
JOIN   edges  x ON x.start_id = o.node_id AND x.type = 'officer_of'
JOIN   entity e ON e.node_id  = x.end_id
WHERE  e.name = 'Exaltation Limited'
  AND  x.link LIKE '%shareholder%';
```

> "`o`, `r` and `e` are aliases. WHERE and ORDER BY are what you expect. RETURN is SELECT, moved to the end so the query reads in the order it runs. The two ON clauses became one arrow."

**2. Query 6: OPTIONAL MATCH is LEFT JOIN (2.5 min).** Paste this one.

```cypher
// Query 6
MATCH (e:Entity {name: 'Exaltation Limited'})
OPTIONAL MATCH (e)<-[r:OFFICER_OF]-(o:Officer)
OPTIONAL MATCH (e)<-[:INTERMEDIARY_OF]-(i:Intermediary)
OPTIONAL MATCH (e)-[:REGISTERED_ADDRESS]->(a:Address)
RETURN e.name, e.jurisdiction_description,
       collect(DISTINCT o.name + ' (' + r.link + ')') AS officers,
       collect(DISTINCT i.name) AS intermediaries,
       collect(DISTINCT a.address) AS addresses;
```

**Expect:** one row. Six officers, one intermediary (CHILD & CHILD), and an empty address list.

> "This company has no registered address in the extract. With a plain MATCH the whole row would vanish, exactly like an inner join. `collect` is your `array_agg`. And DISTINCT is there for the reason you already know: three joins off one row fan out."

**3. Query 7: the shared neighbour (2.5 min).** Type this one live and draw the shape in the air.

```cypher
// Query 7
MATCH (me:Officer {name: 'LEYLA ILHAM QIZI ALIYEVA'})
      -[:REGISTERED_ADDRESS]->(a:Address)<-[:REGISTERED_ADDRESS]-(other)
RETURN a.address, labels(other) AS type, other.name;
```

**Expect:** three rows, all at `7 S. Vurgun Street; Baku AZ1 001; Azerbaijan`: ARZU ILHAM QIZI ALIYEVA, Arzu Ilham Qizi Aliyeva, Leyla Ilham Qizi Aliyeva.

> "Two arrows pointing in at a hub. In SQL this is a self-join through the edge table. Notice `(other)` has no label. I am asking for anything at this address, officer or company. In SQL that is a UNION across tables."

One more thing a SQL person will wonder about: there is no `other <> me`. A pattern never walks the same relationship twice, so the start node does not come back as its own neighbour.

**4. Query 8: who shares companies with this person (3 min).**

```cypher
// Query 8
MATCH (me:Officer {name: 'Leyla Aliyeva'})
      -[:OFFICER_OF]->(e:Entity)<-[:OFFICER_OF]-(other:Officer)
RETURN other.name AS co_officer, collect(e.name) AS companies
ORDER BY size(companies) DESC;
```

**Expect:** eight rows. Arzu Aliyeva is first with three shared companies: Exaltation Limited, KINGSVIEW DEVELOPMENTS LIMITED and UF UNIVERSE FOUNDATION. Mehriban Aliyeva appears once, through UF UNIVERSE FOUNDATION.

> "That last row is half of the answer to our opening question, and we found it by drawing a shape. But we had to know the shape was two hops through a company."

**Bridge to the next segment.** Every query so far had a fixed number of hops. Ask the room: "What if you do not know how many?"

## Segment 4 (0:22 to 0:32): Traversals

A traversal starts at one node and walks outward along relationships. This segment goes from a fixed walk, to a walk of unknown length, to the shortest walk between two nodes.

**1. Query 9: a fixed chain (2 min).**

```cypher
// Query 9
MATCH (o:Officer {name: 'Leyla Aliyeva'})
      -[:OFFICER_OF]->(e:Entity)<-[:INTERMEDIARY_OF]-(i:Intermediary)
RETURN e.name AS company, i.name AS set_up_by;
```

**Expect:** three rows.

| company | set\_up\_by |
| --- | --- |
| Exaltation Limited | CHILD & CHILD |
| UF UNIVERSE FOUNDATION | MOSSACK FONSECA & CO. (U.K.) LIMITED |
| KINGSVIEW DEVELOPMENTS LIMITED | NAUTILUS TRUST COMPANY LIMITED |

> "One person, three companies, three different firms. To go one hop further I extend the drawing. In SQL, every extra hop is two more joins: one to the edge table, one to the node table."

**2. Query 10: a walk of unknown length (3.5 min).** First as a picture.

```cypher
// Query 10a
MATCH p = (o:Officer {name: 'Leyla Aliyeva'})-[*1..2]-(n)
RETURN p;
```

**Expect:** 15 nodes: the start, 3 entities, 8 officers and 3 intermediaries.

> "The star means 'repeat'. One to two hops, any relationship type, either direction because there is no arrowhead. `p` is the whole path, a value I can return."

Now as a count. Run it three times, changing only the upper bound to 2, 3, then 4.

```cypher
// Query 10b
MATCH (o:Officer {name: 'Leyla Aliyeva'})-[*1..3]-(n)
WHERE n <> o
RETURN count(DISTINCT n) AS reachable;
```

| Upper bound | Distinct nodes reachable | Run it live? |
| --- | --- | --- |
| 1 | 3 | Yes |
| 2 | 14 | Yes |
| 3 | 3,336 | Yes |
| 4 | 6,309 | Yes, if the dry run was fast |
| 5 | 13,870 | No, quote it |
| 6 | 28,783 | No, quote it |

Stop on the jump from 14 to 3,336 and ask the room why.

> "At two hops we reached three law firms. At three hops we reached every other company those firms ever set up: 3,322 of them. That is a hub. Graphs have them, and they are why you always put an upper bound on the star."

**Optional sample: Query 10c, a quantified path pattern (2 min).** Use it if the room asks "can I repeat a whole pattern, not just one relationship?" To make room, drop Query 14.

The star in Query 10 repeats a single relationship. A quantified path pattern repeats a whole sub-pattern in parentheses, here "officer of a company that has another officer", one or two times.

```cypher
// Query 10c
MATCH (me:Officer {name: 'Leyla Aliyeva'})
      (()-[:OFFICER_OF]->(:Entity)<-[:OFFICER_OF]-(:Officer)){1,2}
      (other:Officer)
WHERE other <> me
RETURN DISTINCT other.name AS officer
ORDER BY officer;
```

**Expect:** ten rows. The eight co-officers from Query 8, plus two that are one company further out: GENERAL NOMINEES LIMITED and THE BEARER.

> "Read the middle line as one unit: out to a company, back to an officer. The braces say do that once or twice. In SQL this is the recursive CTE again, with two joins inside each step."

Then show what the star cannot do: a filter inside the repeated unit, applied at every step.

```cypher
// Query 10d
MATCH (me:Officer {name: 'Leyla Aliyeva'})
      (()-[:OFFICER_OF]->(e:Entity)<-[:OFFICER_OF]-(:Officer)
         WHERE e.jurisdiction = 'BVI'){1,2}
      (other:Officer)
WHERE other <> me
RETURN DISTINCT other.name AS officer
ORDER BY officer;
```

**Expect:** eight rows. Mehriban Aliyeva and Heydar Aliyev drop out, because their only link runs through UF UNIVERSE FOUNDATION, which is registered in Panama.

Quantified path patterns need Neo4j 5.9 or later; the demo database is 5.26.

**3. Query 11: shortest path, explained this time (2 min).**

```cypher
// Query 11
MATCH (a:Officer {name: 'Mehriban Aliyeva'}), (b:Officer {name: 'Leyla Aliyeva'})
MATCH p = shortestPath((a)-[*..6]-(b))
RETURN [n IN nodes(p) | coalesce(n.name, n.address)] AS hops, length(p);
```

**Expect:** `[Mehriban Aliyeva, UF UNIVERSE FOUNDATION, Leyla Aliyeva]`, length 2.

Read it aloud piece by piece. The room can now parse every token:

- Line 1 finds two start points, by index.
- `[*..6]` is the variable-length walk from Query 10, capped at six hops.
- `shortestPath` searches breadth-first and stops at the first route it finds. The recursive CTE could not stop early.
- `nodes(p)` unpacks the path. `coalesce` picks whichever of `name` or `address` the node has.

**4. Query 12: a path is not a relationship (2.5 min).**

```cypher
// Query 12
MATCH (a:Officer {name: 'Mehriban Aliyeva'}),
      (b:Entity {name: 'TIANSHENG INDUSTRY AND TRADING CO., LTD.'})
MATCH p = shortestPath((a)-[*..8]-(b))
RETURN p;
```

**Expect:** a path of length 5. One valid route is Mehriban Aliyeva, UF UNIVERSE FOUNDATION, MOSSACK FONSECA & CO. (U.K.) LIMITED, ALPHA WHOLESALE LTD, MOSSFON SUBSCRIBERS LTD., then the target. The middle hops may differ; several routes of length 5 can exist.

> "The target is the first row of the entity file, a Samoan company picked at random. It is five hops from our officer. Does that mean anything? No. The route runs through a law firm and a nominee shareholder that sits on 3,958 companies. The database found a path. Deciding whether it matters is still your job."

This is the most important caveat in the session. Repeat the ICIJ line here: a connection in this data is not evidence of wrongdoing.

## Segment 5 (0:32 to 0:37): Core concepts

Three ideas explain why the last ten minutes worked: how a hop is executed, what indexes are for, and how the model changes. Show each with something on screen.

**1. Query 13: index-free adjacency (2 min).** Speak to the people who read query plans for a living.

```cypher
// Query 13
PROFILE
MATCH (o:Officer {name: 'Leyla Aliyeva'})
      -[:OFFICER_OF]->(e:Entity)<-[:INTERMEDIARY_OF]-(i:Intermediary)
RETURN e.name, i.name;
```

**Expect:** a plan that begins with an index seek on `Officer(name)`, followed by two expand steps. Compare the database hits with the 559,600 nodes in the graph. Note the exact operator names and hit counts in your dry run.

> "One index lookup, to find where to start. After that, no index at all. Each node holds direct references to its own relationships, so a hop is following a pointer. The cost follows how many relationships you touch, not how big the tables are. An indexed join pays a lookup at every hop, and that lookup grows with the table."

**2. What indexes are for (30 sec).** No query needed.

> "In a relational database, indexes make joins fast. Here, an index only finds your starting point. That is why this graph has an index on names and none on the relationships between tables."

**3. Query 14: the model changes without a migration (2 min).** Return to the seed from Query 4: six officer records, two people.

```cypher
// Query 14a - writes to the graph
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

**Expect:** four rows: `leyla aliyeva` 3, `arzu aliyeva` 3, `nurali aliyev` 2, `mr. galiyev` 2.

```cypher
// Query 14b
MATCH path = (p:Person)<-[:IDENTITY]-(o:Officer)-[:OFFICER_OF]->(e:Entity)
RETURN path;
```

> "I just added a new kind of node and a new kind of relationship. No ALTER TABLE, no migration, and none of the earlier queries changed. MERGE is an upsert: run it twice and nothing is duplicated."

Do not walk through 14a line by line. The point is what happened to the model, not the string handling. If someone spots `mr. galiyev`, agree: substring matching is crude, and that is a data-quality point, not a graph one.

**Clean up straight after the session:**

```cypher
MATCH (p:Person) DETACH DELETE p;
```

**4. When not to use a graph (30 sec).**

> "If your question is 'total by region by quarter', stay where you are. Scanning and aggregating whole tables is what relational and columnar engines are built for. A graph earns its place when the question starts somewhere and asks what it is connected to."

## Wrap-up and questions (0:37 to 0:40)

Close by pointing back at the vocabulary table still on the whiteboard, then restate the three ideas in one breath.

> "Relationships are stored, not computed. A query is a drawing of the shape you want. And depth is cheap, as long as you bound it and watch for hubs."

Put Query 1 back on screen as the last thing they see. They can now read all three lines.

**Questions this audience usually asks**

| Question | Short answer |
| --- | --- |
| Is there any schema at all? | Yes, where you ask for it. This graph has uniqueness constraints on `node_id`; see `cypher/00_constraints.cypher`. What is optional is declaring every property up front. |
| Is it transactional? | Yes. Neo4j is ACID; writes such as Query 14a run in a transaction. |
| Could I do this in Postgres with recursive CTEs? | For shallow, known shapes, yes. It gets harder to write and slower to run as depth grows and the route is unknown. |
| Do I need a relationship in each direction? | No. Store it once, in the direction that reads naturally. A relationship can be walked either way at the same cost. |
| Is Cypher proprietary? | It is the basis of GQL, the ISO graph query language standard published in 2024. |
| How would our relational data get in? | Tables become labels, foreign keys become relationships, and join tables become relationships with properties. `cypher/01` to `05` do exactly this from CSV. |
| What do you do about hubs? | Bound every variable-length pattern, restrict relationship types, and exclude known hubs such as nominee officers. |

## Appendix

**SQL to Cypher cheat sheet.** Hand this out or leave it on the last slide.

| SQL | Cypher |
| --- | --- |
| `SELECT` | `RETURN` |
| `FROM a JOIN b ON ...` | `MATCH (a)-[:REL]->(b)` |
| `LEFT JOIN` | `OPTIONAL MATCH` |
| `WHERE col = 'x'` | `WHERE n.prop = 'x'`, or inline `{prop: 'x'}` |
| `GROUP BY` | Implicit: every non-aggregated item in `RETURN` |
| `HAVING` | `WITH ... WHERE` |
| `array_agg()` | `collect()` |
| Subquery or CTE | `WITH` |
| `INSERT` | `CREATE` |
| Upsert | `MERGE` |
| `WITH RECURSIVE` | `-[*1..n]-` |
| `EXPLAIN ANALYZE` | `PROFILE` |

**Known pitfalls on the day**

- **Names are exact and case-sensitive.** `Leyla Aliyeva` and `LEYLA ILHAM QIZI ALIYEVA` are different nodes. Copy names from this doc; do not retype them.
- **Some names are not unique.** Two intermediaries are called `MOSSACK FONSECA & CO.`: one has 4,364 relationships, the other has 1. Do not anchor a live query on that name.
- **Never run an unbounded `[*]`.** If someone asks for it, explain why instead.
- **Do not return Query 10 as a graph at depth 3.** That is 3,336 nodes; Browser will truncate or stall. Use the count.
- **Leftover `:Person` nodes change earlier results.** After Query 14a, Query 2 shows a fifth row and Query 10 reaches extra nodes. Run the cleanup before any repeat session.
- **Query 12 can draw a different route each run.** The length stays 5; do not promise specific middle nodes.

**If something fails live**

- Keep a screenshot of the result of Queries 1, 10a and 12 from your dry run. Those three carry the session.
- If a query hangs, stop it with the Browser stop button and move on to the next one. Do not debug in front of the room.
- If asked to look someone up, use the full-text index rather than `CONTAINS`:

```cypher
CALL db.index.fulltext.queryNodes('node_name', 'exaltation~') YIELD node, score
RETURN labels(node), node.name, score
ORDER BY score DESC LIMIT 10;
```

**Where the material comes from.** Queries 1, 4, 6, 7, 11 and 14 are adapted from `TUTORIAL.md` in this repo. Data: the [ICIJ Offshore Leaks Database](https://offshoreleaks.icij.org/), Panama Papers extract, current through 2015.
