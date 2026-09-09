# graph-computing

Graph algorithms, graph databases and use cases.

## Use cases

### [neo4j/panama-papers](neo4j/panama-papers/)

Loads the ICIJ Panama Papers extract — 559,600 nodes and 674,102 relationships —
into Neo4j with Cypher, and teaches Cypher through it.

- **[Load scripts](neo4j/panama-papers/cypher/)** — constraints, batched
  `LOAD CSV` imports, indexes, and a verification pass with expected counts.
- **[README](neo4j/panama-papers/README.md)** — the graph model and the
  reasoning behind it.
- **[TUTORIAL](neo4j/panama-papers/TUTORIAL.md)** — 15 progressive scenarios,
  from `MATCH` basics to entity resolution and path finding, built on real
  records in the data.

```bash
cd neo4j/panama-papers
NEO4J_HOME=/path/to/neo4j NEO4J_PASSWORD=yourpassword ./cypher/load_all.sh
```

> The CSVs are stored with [Git LFS](https://git-lfs.com). Run `git lfs install`
> before cloning, or `git lfs pull` afterwards, to fetch them.

Data is from the [ICIJ Offshore Leaks Database](https://offshoreleaks.icij.org/)
under the ODbL. There are legitimate uses for offshore companies — presence in
this data is not evidence of wrongdoing.
