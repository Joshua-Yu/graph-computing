# Network Search: Graph Modeling Guideline

| | |
|---|---|
| **Status** | Draft for review |
| **Date** | 2026-10-07 |
| **Applies to** | The Network Search customer graph in Neo4j, and everything that reads or writes it: Day 0 loaders, Kafka consumers, Hume Orchestra workflows, risk scoring, investigation queries |

## 1. Purpose

Neo4j is new to bank ABC. This guideline sets out how we model the Network Search graph so that every team writing to it produces the same shapes, and every team reading from it can rely on them.

It covers what becomes a node, a relationship or a property; how things are named and identified; how time, provenance and risk outputs are represented; and the patterns to avoid. It does not cover Cypher style, ingestion design or infrastructure, which have their own documents.

Where this guideline says **must**, a change that breaks the rule needs an ADR. Where it says **should**, deviate if you have a reason and note it in the pull request.

Section 14 lists decisions that are still open. Rules that depend on them are marked *(open)*.

## 2. What the graph is for

The model exists to answer a small set of questions quickly. Every modeling choice is judged against them.

| # | Question | Typical shape |
|---|---|---|
| Q1 | Who and what is connected to this party or account, within N hops? | Variable-length expansion from one node |
| Q2 | Which parties share a phone, email, device, address or identity document? | Party → identifier → Party |
| Q3 | Where did the money go, and where did it come from? | Account → Account chains, ordered in time |
| Q4 | Is this account connected to known fraud, a mule account or an open case? | Shortest path to a flagged node |
| Q5 | What does this account's neighbourhood look like (size, density, risk mix)? | Aggregation over a neighbourhood, used as scoring features |
| Q6 | Why did this account receive this score? | Read back the paths and features behind a score |
| Q7 | What did this network look like on a given date? | Any of the above, filtered by time |

Two consequences follow:

- **Model for traversal, not for storage.** The graph is not a copy of the warehouse. A source attribute enters the graph only if it is used to connect, filter, score or explain. Everything else stays in the warehouse and is fetched by ID when needed.
- **Design from the question.** Before adding a label or relationship type, write the Cypher for the question it serves. If you can't, it doesn't belong yet.

## 3. Core model

### 3.1 Nodes

| Label | What it represents | Business key | Notes |
|---|---|---|---|
| `Party` | A person or organisation known to the bank | `partyId` | Always carries a second label: `Person` or `Organisation` |
| `Account` | A product holding with the bank, or an external account seen in transactions | `accountId` | Product type is a property (`productType`), not a node. External accounts carry the extra label `ExternalAccount` |
| `Service` | A facility a party or account is enrolled in, such as online banking, a card or a payment alias *(open)* | `serviceId` | |
| `Transaction` | A single movement of money | `transactionId` | See 3.4 |
| `Phone` | A phone number | `number` | Normalised to E.164 |
| `Email` | An email address | `address` | Trimmed and lower-cased |
| `Device` | A device used to access a channel | `deviceId` | Fingerprint supplied by the channel |
| `IpAddress` | An IP address seen on a session or transaction | `ip` | |
| `Address` | A physical address | `addressId` | ID from address standardisation, not free text |
| `IdentityDocument` | A passport, licence or similar | `documentKey` | Document type + issuer + number, hashed (see section 10) |
| `Alert` | A risk or fraud alert raised on a party or account | `alertId` | Derived data, see section 9 |
| `Case` | An investigation case in the Hume workflow | `caseId` | Derived data, see section 9 |

### 3.2 Relationships

| Pattern | Meaning | Key properties |
|---|---|---|
| `(:Party)-[:HOLDS]->(:Account)` | Party is an owner of the account | `role`, `validFrom`, `validTo` |
| `(:Party)-[:IS_SIGNATORY_OF]->(:Account)` | Party can operate but does not own | `validFrom`, `validTo` |
| `(:Party)-[:RELATED_TO]->(:Party)` | Declared relationship: director, guarantor, spouse, beneficial owner | `relationshipType`, `validFrom`, `validTo` |
| `(:Party)-[:ENROLLED_IN]->(:Service)` | Party uses the service | `validFrom`, `validTo` |
| `(:Service)-[:LINKED_TO]->(:Account)` | Service operates on the account | `validFrom`, `validTo` |
| `(:Party)-[:HAS_PHONE]->(:Phone)` | Contact detail on record | `usage`, `validFrom`, `validTo` |
| `(:Party)-[:HAS_EMAIL]->(:Email)` | Contact detail on record | `usage`, `validFrom`, `validTo` |
| `(:Party)-[:HAS_ADDRESS]->(:Address)` | Residential, postal or registered address | `usage`, `validFrom`, `validTo` |
| `(:Party)-[:IDENTIFIED_BY]->(:IdentityDocument)` | Document presented for identification | `verifiedAt` |
| `(:Party)-[:USED_DEVICE]->(:Device)` | Party logged in from the device | `firstSeenAt`, `lastSeenAt`, `sessionCount` |
| `(:Device)-[:SEEN_AT]->(:IpAddress)` | Device connected from the IP | `firstSeenAt`, `lastSeenAt` |
| `(:Account)-[:SENT]->(:Transaction)` | Account was debited | |
| `(:Transaction)-[:CREDITED_TO]->(:Account)` | Account was credited | |
| `(:Transaction)-[:INITIATED_FROM]->(:Device)` | Device used to initiate the payment | |
| `(:Account)-[:TRANSFERRED_TO]->(:Account)` | Summary of all money sent between two accounts | `txCount`, `totalAmountMinor`, `currency`, `firstAt`, `lastAt` |
| `(:Alert)-[:RAISED_ON]->(:Party\|:Account)` | Subject of the alert | |
| `(:Case)-[:INCLUDES]->(:Alert\|:Party\|:Account)` | Item under investigation in the case | `addedAt`, `addedBy` |

### 3.3 Party and customer

Source systems use both "customer" and "party". In the graph there is one term:

- The label is `Party`, and the key is `partyId`. **Never** introduce a `Customer` label or a `customerId` property.
- A customer is a party that holds or has held an account. That is a fact you derive from `HOLDS`, not a separate kind of node. Non-customers (beneficiaries, directors, counterparties) are also `Party`.
- The source field name is preserved only in mappings (`model/mappings/`) and data contracts.

### 3.4 Transactions

A transaction is a **node**, not a relationship, because it connects to more than two things (two accounts, a device, sometimes an alert) and because investigators need to select and annotate individual transactions.

Traversing through transaction nodes is expensive for money-flow questions over long periods, so the model also keeps a **summary relationship**, `TRANSFERRED_TO`, between each pair of accounts. It is maintained by the ingestion path at the same time as the transaction is written.

- Use `TRANSFERRED_TO` for Q1, Q4 and Q5 (who is connected, how strongly).
- Use `Transaction` nodes for Q3 and Q6 (exact sequence, amounts and evidence).
- `TRANSFERRED_TO` is derived from transactions and must be rebuildable from them.

Transaction nodes are the largest part of the graph by far. Only a rolling window is kept in Neo4j *(open: window length)*; the summary relationship keeps its totals after old transactions are removed.

## 4. Node, relationship or property?

Use this order of tests:

1. **Will two or more things connect through it?** Make it a node. This is why phone, email, device and address are nodes: a shared identifier is the single most useful signal for Q2, and it is only traversable if it is a node.
2. **Is it a fact about how two things relate?** Make it a relationship, with the qualifying details as relationship properties.
3. **Does the fact involve more than two things, or need its own relationships?** Make it a node (as with `Transaction`, `Alert`, `Case`).
4. **Otherwise** it is a property, and only if it passes the test in section 2.

Further rules:

- **Low-cardinality values are properties, not nodes.** Country, product type, channel, currency and status as nodes become supernodes (section 8) and connect everything to everything.
- **Sub-types are extra labels, not a `type` property**, when queries routinely start from the sub-type: `Party:Person`, `Party:Organisation`, `Account:ExternalAccount`. Keep it to one level; don't build label hierarchies.
- **States are properties, not labels.** `status: 'CLOSED'` rather than a `ClosedAccount` label. The exception is a small set of investigation markers that queries filter on constantly, listed in section 9.
- **One relationship per fact, one direction.** Never store an inverse (`HELD_BY` alongside `HOLDS`). Cypher traverses either way at the same cost.
- **Specific relationship types beat a generic type with a property.** `HAS_PHONE` and `HAS_EMAIL`, not `HAS {kind: 'phone'}`. The type is what lets a traversal skip irrelevant edges. `RELATED_TO` is the deliberate exception, because the set of declared party relationships is long and source-defined.

## 5. Naming

| Element | Convention | Example |
|---|---|---|
| Node label | PascalCase, singular noun | `IdentityDocument` |
| Relationship type | UPPER_SNAKE_CASE, verb phrase, reads source to target | `IS_SIGNATORY_OF` |
| Property | camelCase | `openedDate` |
| Business key | `<entity>Id` | `partyId`, `accountId` |
| Date property | suffix `Date` | `openedDate` |
| Timestamp property | suffix `At` | `lastSeenAt` |
| Boolean property | prefix `is` or `has` | `isJoint` |
| Monetary amount | suffix `Minor`, paired with `currency` | `amountMinor`, `currency` |
| Constraint and index | `<label>_<property>_<kind>` | `party_partyId_unique` |

Use bank ABC's business vocabulary from `docs/01-overview/glossary.md`. Don't carry source column names (`CUST_NO`, `ACCT_STAT_CD`) into the graph.

## 6. Identity and keys

- **Every node label must have exactly one business key, backed by a uniqueness constraint.** The constraint goes in before any data is loaded; without it `MERGE` scans the whole label and concurrent writers create duplicates.
- **Never use Neo4j's internal IDs** (`elementId()`, `id()`) as keys, in stored data, in Kafka messages or in Hume configuration. They are not stable across reloads.
- **Keys are strings**, even when the source value looks numeric. Leading zeros matter in account numbers.
- **Keys carry no meaning.** Don't parse a branch or product out of an `accountId`; store those as properties.
- **Identifier nodes are keyed on the normalised value**, so that the same phone number arriving from two systems lands on one node. Normalisation rules live in one shared library (`src/common/`) used by Day 0 and Kafka alike.
- **External accounts** are keyed on institution code plus account number, in the same `accountId` namespace with a prefix (`EXT:<institution>:<number>`), so a payment to an external account that later turns out to be on-us can be reconciled.

### Entity resolution

Sources outside the party master will describe people the bank already knows. *(open: matching approach)*

- Records that match an existing party on the party master ID attach to that `Party`.
- Records that don't are created as their own `Party`, keyed with a source prefix.
- A suspected match is recorded as `(:Party)-[:POSSIBLY_SAME_AS {score, method, matchedAt}]->(:Party)`. **Nodes are never merged automatically.** A merge destroys the evidence for it and cannot be undone when the match was wrong.

## 7. Time, provenance and change

### 7.1 Time

- Use Neo4j's native `date` and `datetime` types, never strings or epoch numbers. Store `datetime` in UTC.
- A relationship that can start and end **must** carry `validFrom` and `validTo`. An open-ended fact has no `validTo` property; there is no `isCurrent` flag to fall out of sync.
- When a fact ends, set `validTo`. **Don't delete the relationship.** A party's former address and a closed joint holding are exactly what Q7 and many fraud patterns look for.
- When the same pair is related more than once over time (a party moves back to an old address), each period is its own relationship, distinguished by `validFrom`.
- Activity relationships (`USED_DEVICE`, `SEEN_AT`, `TRANSFERRED_TO`) carry `firstSeenAt` / `lastSeenAt` or `firstAt` / `lastAt` instead, and are updated in place.

### 7.2 Provenance

Every node and every sourced relationship **must** carry:

| Property | Meaning |
|---|---|
| `sourceSystem` | System of record the fact came from |
| `sourceUpdatedAt` | When the source says the fact last changed |
| `ingestedAt` | When Network Search last wrote it |
| `loadId` | Day 0 batch ID, or Kafka topic-partition-offset |

These are what make reconciliation, replay and "why is this here?" answerable.

### 7.3 Writes must be idempotent and order-tolerant

The Day 0 load and the Kafka consumers write the same model with the same keys. Kafka events can be redelivered or arrive out of order, so every write follows one shape: `MERGE` on the business key only, then apply properties only if the incoming event is newer.

```cypher
MERGE (p:Party {partyId: $partyId})
  ON CREATE SET p.ingestedAt = datetime()
WITH p
WHERE p.sourceUpdatedAt IS NULL OR p.sourceUpdatedAt < datetime($sourceUpdatedAt)
SET p += $properties,
    p.sourceSystem    = $sourceSystem,
    p.sourceUpdatedAt = datetime($sourceUpdatedAt),
    p.ingestedAt      = datetime(),
    p.loadId          = $loadId
```

- **`MERGE` on the key alone.** Putting other properties in the `MERGE` pattern creates a duplicate whenever one of them differs.
- **`MERGE` nodes first, then the relationship between them**, in separate clauses. Merging a whole path creates duplicate nodes when any part of it is missing.
- **An event may reference a node that hasn't arrived yet** (a transaction before its account). Create the missing node as a stub with the key and provenance only; the later event fills it in. Never drop the event.
- **Deletes from source are soft.** Set `validTo` or `status`; hard deletion is reserved for retention and privacy erasure jobs.
- A Day 0 load of a dataset and a Kafka replay of the same dataset **must** produce an identical graph. This is a test in `tests/reconciliation/`.

## 8. Supernodes

A supernode is a node with so many relationships that any traversal reaching it explodes. In this graph they are predictable:

| Likely supernode | Why |
|---|---|
| The bank's own settlement, suspense and fee accounts | Every transaction touches them |
| Large billers, merchants, payroll and government payers | Millions of counterparties |
| Branch, head-office and PO box addresses used as a default | Shared by unrelated parties |
| Call-centre and placeholder phone numbers, shared corporate email domains | Entered as defaults |
| Shared IP addresses (carrier NAT, corporate proxies, VPN exits) | Thousands of unrelated devices |
| Kiosk and branch devices | Shared by design |

Rules:

- **Keep them out at source where they carry no signal.** Placeholder values (`0000000000`, `unknown@...`) are dropped by the shared normalisation library and never become nodes.
- **Mark the ones that stay.** A scheduled job sets `isHighDegree = true` on any node above a degree threshold (start at 10,000 and tune). Internal bank accounts are additionally labelled `InternalAccount` at load.
- **Traversals must not expand through marked nodes.** Network search, path-finding and feature queries stop at a high-degree node: they may report it, but not pass through it. This rule is part of every query in `cypher/queries/` and `cypher/fraud-patterns/`.
- **Never model a category as a node** (section 4). It is a supernode by construction.

## 9. Risk scores, alerts and other derived data

Sourced facts and things we computed must stay distinguishable, so that a score can never be mistaken for evidence and derived data can be wiped and rebuilt.

- **The current score is a set of properties** on the `Party` or `Account`: `riskScore`, `riskBand`, `riskModelVersion`, `riskScoredAt`. Queries filter on these constantly, so they are indexed.
- **Score history is not kept in the graph.** It goes to the warehouse. The graph holds the current state.
- **Alerts and cases are nodes**, because they connect to several subjects and investigators navigate through them.
- **Investigation markers are labels**, and only these: `ConfirmedFraud`, `SuspectedMule`, `Watchlisted`. They are set by the investigation workflow, never by ingestion, and each carries `markedAt`, `markedBy` and `caseId`.
- **Derived relationships** (for example a `SHARES_IDENTIFIER_WITH` shortcut, or community membership from a graph algorithm) must carry `derivedBy` (job or algorithm name and version) and `derivedAt`, must not carry `sourceSystem`, and must be listed in `model/graph-schema/relationships/`.
- **A score must be explainable from the graph (Q6).** A scoring feature that can't be traced back to nodes and relationships an investigator can open is not acceptable. Store the contributing feature values with the alert, not only the final number.

## 10. Properties and data types

- **Money is an integer in minor units** (`amountMinor: 125050` with `currency: 'AUD'`). Neo4j has no decimal type, and floating-point amounts don't reconcile.
- **Don't store nulls or empty strings.** Leave the property off.
- **No JSON or delimited strings in a property.** If it has structure, model the structure.
- **Lists are for small, fixed sets of simple values** only. A list that grows (transaction IDs, login history) is a set of nodes.
- **No large text or binary content.** Store a reference.
- **Enumerations are upper-case codes** from the glossary: `status: 'ACTIVE'`.
- **Every node has a `displayName`** suitable for showing in Hume: a masked account number, a party's name, a formatted phone number. Investigators should never see a bare key.

### Personal information

The graph holds personal information about bank customers, and every property is governed by `docs/10-security-governance/pii-handling.md`.

- **Minimise.** If matching only needs to know that two values are equal, store a keyed hash and not the value. Identity document numbers are always stored hashed.
- **Keep what investigators must read** (names, phone numbers, addresses) in clear, classified in `model/graph-schema/properties/`, and restricted with Neo4j role-based access control at property level.
- **Never** store credentials, card numbers, security answers or full dates of birth where year of birth is enough.
- **No production data** in `test-data/`, `notebooks/` or examples.

## 11. Constraints and indexes

- **Every business key has a uniqueness constraint.** Mandatory properties (key, provenance) should have existence constraints.
- **Index what queries look up or filter by, and nothing else:** `riskBand`, `status`, `Transaction.bookedAt`, `isHighDegree`. Each index slows every write.
- **Name search uses a full-text index** on `Party.displayName` and aliases. Don't use `CONTAINS` on an unindexed property.
- **All constraints and indexes are created through `cypher/migrations/`**, never by hand and never by a loader or Hume workflow.

```cypher
CREATE CONSTRAINT party_partyId_unique IF NOT EXISTS
FOR (p:Party) REQUIRE p.partyId IS UNIQUE;

CREATE CONSTRAINT account_accountId_unique IF NOT EXISTS
FOR (a:Account) REQUIRE a.accountId IS UNIQUE;

CREATE INDEX transaction_bookedAt_range IF NOT EXISTS
FOR (t:Transaction) ON (t.bookedAt);

CREATE FULLTEXT INDEX party_name_fulltext IF NOT EXISTS
FOR (p:Party) ON EACH [p.displayName, p.aliases];
```

## 12. Hume

- **The Hume schema mirrors this model one to one.** Don't define classes or relationships in Hume that aren't in `model/graph-schema/`.
- **Orchestra workflows are writers like any other.** They use the same business keys, the same `MERGE` shape (7.3) and the same provenance properties, with `sourceSystem` set to the workflow name.
- **Investigation state is written only through the workflow**: `Case` nodes, `INCLUDES` relationships and the marker labels in section 9.
- **Keep the label and relationship-type count small.** Every addition is one more thing an investigator has to understand on the canvas.

## 13. Patterns to avoid

| Don't | Because | Do instead |
|---|---|---|
| Copy warehouse tables into nodes column for column | Bloats the graph and adds nothing to traversal | Load only what connects, filters, scores or explains |
| Model join tables as nodes | A join table is a relationship | `(:Party)-[:HOLDS]->(:Account)` |
| Put a phone or email as a property on `Party` | Sharing becomes invisible to traversal | Identifier nodes |
| Create nodes for country, product type, channel, status | Supernodes | Properties |
| One generic `LINKED_TO` or `HAS` for everything | Traversals can't skip irrelevant edges | Specific types |
| Store both directions of a relationship | Doubles writes, drifts out of sync | One direction |
| `MERGE` on a full pattern or on non-key properties | Duplicates | `MERGE` on key, then `SET` |
| Overwrite history on update | Loses Q7 | `validFrom` / `validTo` |
| Auto-merge parties that look alike | Irreversible when wrong | `POSSIBLY_SAME_AS` |
| Mix scores and markers in with sourced facts, unlabelled | Scores get read as evidence | Section 9 |
| Unbounded variable-length paths (`-[*]-`) | Query never returns on a real network | Bound the hops, stop at high-degree nodes |

## 14. Open decisions

| # | Decision | Why it matters | Proposed owner |
|---|---|---|---|
| 1 | Exact definition of `Service` at bank ABC, and whether cards and payment aliases are services or their own labels | Determines the key and the relationships in 3.2 | Data architecture |
| 2 | Transaction retention window in Neo4j | Dominates graph size and hardware | Solution architecture, fraud operations |
| 3 | Party matching approach for non-warehouse sources, and whether a party master ID is available on all of them | Determines how much `POSSIBLY_SAME_AS` is needed | Data architecture |
| 4 | Degree threshold for `isHighDegree` | Trade-off between missed connections and query time | Graph engineering, after Day 0 profiling |
| 5 | Which personal-information properties are held in clear | Access control design and privacy assessment | Security and privacy |
| 6 | Whether individual card transactions are loaded, or payments only | Volume, and relevance to account risk | Fraud operations |

Each should be closed with an ADR in `docs/12-decisions/adr/`.

## 15. Changing the model

1. Write the question and the Cypher that the change serves.
2. Update the schema definition in `model/graph-schema/` and the mapping in `model/mappings/`.
3. Add a migration in `cypher/migrations/` for constraints, indexes and any backfill.
4. Update the Day 0 loader and the Kafka consumer together, and the Hume schema.
5. Raise an ADR if the change adds a label or relationship type, changes a business key, or breaks a **must** in this guideline.

### Review checklist

- [ ] The change is tied to a question in section 2, with the query written.
- [ ] Each new label has one business key and a uniqueness constraint.
- [ ] Names follow section 5 and use glossary terms; "customer" does not appear in the graph.
- [ ] Nothing low-cardinality has become a node.
- [ ] Relationships that can end carry `validFrom` and `validTo`.
- [ ] Provenance properties are set on every write.
- [ ] Writes are idempotent and guarded by `sourceUpdatedAt`.
- [ ] Day 0 and Kafka paths produce the same result for the new data.
- [ ] Likely supernodes are identified and handled.
- [ ] New properties are classified for personal information.
- [ ] Derived data is marked as derived.
- [ ] The Hume schema is updated to match.
