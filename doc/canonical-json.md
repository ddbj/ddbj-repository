# DDBJ Record JSON Canonicalization Specification (canonical_version: 2)

## Status / Versioning

**Status:** Draft for Phase 2. Identifier: `ddbj-canon/v2`. Frozen on first use.

### Version History

**v2 (2026-07-31).** `accession` is no longer stripped for diff. It failed §4.1's own test — an accession is assigned once and does not change between regenerations, so it is not volatile; it was listed on an authorship argument ("archive-assigned, not curator data"), which is a different criterion. The consequence of stripping it was that accession issuance — the most consequential thing a curator does — produced an empty patch and left no trace in the chain, so the typed column became the sole authority and the stored record could disagree with it. Downstream code had begun to route around the gap: the BS public-XML renderer joins v3 samples on `alias` with a comment naming the strip list as the reason it cannot join on accession.

The rule this restores: **every change the record carries is expressible as a patch.** Where a comparison wants to ignore archive-assigned identity, it asks for that at comparison time (`for_diff: true` is still available as a predicate) rather than having the diff generator withhold it.

Migration: no chain rewrite is required for replay — `apply` is pure RFC 6902, so v1 chains replay identically under either strip list. Records predating v2 may carry an accession the chain never explains (importer baselines do, `append_update!`-only chains do not). The migrated corpus is rebuilt from source rather than reconciled.

All Open Questions (§7) must be resolved before the first production canonicalization; otherwise freeze immediately forces a bump. Any subsequent change to the rules below — sort registry, strip list, string normalization — requires the next `ddbj-canon` version, plus: (a) a documented migration that re-canonicalizes all stored records and replays all patch chains under the new rules; (b) coexistence (stored patches retain their original `canon` tag; verifiers dispatch by tag); (c) extension of golden vectors to cover the new version alongside all prior versions. The XML c14n 1.0 / 1.1 / exclusive precedent is the cautionary tale: we tag from day one.

**Relation to `schema_version`.** Independent: a schema-only change requires no canon bump iff canonical output is byte-identical on every previously valid record; a canon-only change always bumps; both together ship as a coordinated bump with one migration. CI maintains a frozen corpus of `(record, schema_version, canonical_version, expected_sha256)`; any perturbation without a version bump fails the build.

## 1. Scope and Base Format

### 1.1 Purpose

Defines `ddbj-canon/v2`, a deterministic byte-identical serialization of DDBJ Record v3 JSON, so content-addressable hashing, RFC 6902 patch generation, and chain replay are reproducible across implementations and time. Semantically equivalent records — differing only in key order, whitespace, number formatting, or unordered-collection order — produce byte-identical canonical output and identical SHA-256 digests.

### 1.2 Scope

Applies to `Submission#ddbj_record` (user-uploaded), `Submission#current_record` (head-of-chain snapshot), `SubmissionUpdate#patch` payloads after application (§1.6 covers the patch document itself), and any intermediate state used for diff generation.

Out of scope: HTTP request/response bodies (free-form JSON per RFC 8259); schema validation (assumed already passed); display formatting.

### 1.3 Base Format

JSON per RFC 8259: UTF-8 with no BOM; NFC on all string leaves and object keys except the `SEQUENCE` class (§2.2); no comments, no trailing commas, no inter-token whitespace. Top-level may be any JSON value (RFC 7493 I-JSON); v3 records are always objects. The `SEQUENCE` class is **byte-streaming compatible** — never materialized in memory, pairing with `DDBJRecord::StreamingParser` for multi-GB assemblies.

### 1.4 Relationship to RFC 8785 (JCS)

`ddbj-canon/v2` is **RFC 8785 plus a versioned delta**. Use a conforming JCS library as the inner serializer.

From RFC 8785 verbatim: UTF-16 code-unit object-key sort; ES262 §7.1.12.1 number serialization; minimal string escaping (`\"`, `\\`, controls as `\u00xx`, else raw UTF-8); no inter-token whitespace.

Added/replaced: array ordering via per-path classification (§3); NFC on string leaves and keys except `SEQUENCE`; volatile-field stripping (§4) under `for_diff=true`; number type discipline (schema-pinned int vs decimal; identifier numerics as strings).

### 1.5 Output Encoding

Serialized as UTF-8 per the above. Storage layers must not re-encode, re-indent, or alter the bytes. SHA-256 is over the raw canonical bytes. Two records have the same identity iff their canonical bytes are equal under the same `canonical_version`.

### 1.6 Canonicalization of JSON Patch Documents

For content-addressing patches (dedup, audit), the patch has its own canonical form:

- The `ops` array preserves input order — JSON Patch operations are **ordered** (RFC 6902 §4).
- Each op object's keys sort UTF-16 per JCS; the `value` is recursively canonicalized as standalone JSON (no per-path classification, since `path` is the op's target, not the value's position in a record).
- `path` / `from` are single-line strings, NFC-normalized but **not whitespace-collapsed** (JSON Pointer escapes are byte-sensitive).
- `for_diff` does not apply to patches; stripping is record-side only.

## 2. Scalar Value Rules

### 2.1 Object Keys

Object keys are sorted in **ascending UTF-16 code unit order** per RFC 8785. Keys are case-sensitive and lowercase-only in v3.

### 2.2 Strings

Three classes: **single-line**, **multi-line**, **sequence**. Class is determined by JSON Pointer path (§6 table). All comparisons elsewhere in this spec (sort keys, hashes, idempotence) operate on the **post-normalization** string.

#### Single-line and multi-line — normalization order

1. **Unicode NFC** (`unicodedata.normalize('NFC', s)`). Multi-year patch chains cannot tolerate `café` (NFC) vs `café` (NFD) producing different diffs.
2. **Line-ending collapse**: `\r\n` → `\n`, lone `\r` → `\n`.
3. **Trim** leading/trailing whitespace from the whole string.
4. **Per-class whitespace collapse** (below).
5. **Control character check**: forbid U+0000–U+001F except U+0009 (`\t`) and U+000A (`\n`). Reject on ingest.
6. **Empty check**: if the result is `""`, the field is **dropped** (§2.5).

**Whitespace policy is asymmetric and intentional.** We collapse the Unicode whitespace class (which includes U+3000 ideographic space and U+200B ZWSP) but do **not** apply NFKC compatibility folding. Full-width letters survive (`ＤＤＢＪ` stays `ＤＤＢＪ`) while ideographic spaces between them collapse to ASCII U+0020 (`Ｄ　Ｄ　Ｂ　Ｊ` → `Ｄ Ｄ Ｂ Ｊ`). NFKC would fold both — still deferred, pending curator sign-off (it was not part of the v2 bump).

The whitespace character set for collapse: Unicode property `White_Space=Yes` plus U+200B / U+200C / U+200D / U+FEFF.

**Single-line paths** collapse any whitespace run to a single ASCII U+0020. Covers identifier-like fields: every `accession`, `alias`, short `name`, `filename`/`filetype`/`checksum*`, `ror_id`/`url`/`email`, `language_code`/`pubmed_id`/`doi`, all CV strings, INSDC `location`, date strings, EAV `name`/`unit`. See §6 for the table.

**Multi-line paths** (default for string-typed paths not classified single-line or `SEQUENCE`) split on `\n`, collapse horizontal whitespace per line, trim each line, rejoin with `\n`, then outer trim. Preserves paragraph breaks. Covers `description`, free-text `title`, `submission.comments`, `entries[*].comments`, `access_control.policy.policy_text`, EAV `value`, `array_description`, `construction_protocol`.

#### Sequence class — `entries[*].sequence`

Carved out from multi-line to be streamable over multi-GB sequences and to avoid pointless NFC over pure ASCII. Single streaming pass: (1) **no NFC** — pure ASCII alphabet, NFC would be a no-op and forces materialization; (2) **strip all whitespace** (ASCII U+0009/U+000A/U+000D/U+0020 only); (3) **lowercase** every byte (`A-Z` → `a-z`; arbitrary choice, consistent with INSDC dumps); (4) **alphabet check** — every byte must be in `[acgtn]`, reject otherwise; (5) **empty check** per §2.5. Loading the sequence as a single Ruby `String` is non-conformant for production; the streaming codec emits canonical bytes directly to the serializer.

Examples:

```text
"  Foo   bar  "    → "Foo bar"          (single-line)
"Foo\r\n\r\nbar"   → "Foo\n\nbar"       (multi-line, paragraph break kept)
"café" (NFD)       → "café" (NFC)
"ＤＤＢＪ"           → "ＤＤＢＪ"          (NFKC NOT applied)
"Ｄ　Ｄ　Ｂ　Ｊ"     → "Ｄ Ｄ Ｂ Ｊ"        (U+3000 collapsed)
"AcGt\nNnnn"       → "acgtnnnn"         (SEQUENCE)
""                 → DROP field
U+0001 + "abc"     → REJECT (control)
"acgtx" (sequence) → REJECT (alphabet)
```

### 2.3 Numbers

**Integers**: JSON integers — no decimal, no exponent, no leading `+` or zeros, single optional `-`. Safe range `[-(2^53-1), 2^53-1]`. Numeric-typed v3 fields: `samples[*].organism.taxonomy_id`, `experiments[*].library.nominal_length`, `features[*].phase`.

Identifier-like numerics are **strings**, because they may exceed safe range or carry leading zeros: every `accession`, `pubmed_id`, `host_taxid`-style EAV value, `checksum*`. `"3"` and `3` are not equivalent in canonical form; the schema pins each field's type.

**Floats** (`nominal_sdev`, `features[*].score`) follow RFC 8785 §3.2.2 / ES262 §7.1.12.1 (shortest round-trip). ES262 switches to exponent form at `n ≥ 21` digits (§7.1.12.1 step 5); below that, integer-valued floats render without exponent. So `1.0` → `1`, `1.10` → `1.1`, `1e10` → `10000000000`, `1e21` → `1e+21`.

**Forbidden**: `NaN`, `±Infinity`; scientific notation for integer-typed fields; thousands separators or non-`.` decimal. `-0` → `0`.

### 2.4 Booleans

JSON `true` / `false`. No coercion from `"true"` / `1` / `"yes"`.

### 2.5 null and Empty Values

`null` is **never written**. A key whose value is `null`, `""`, `[]`, or `{}` after normalization is **dropped** from its parent object. `0` and `false` are **not** empty.

```json
// Input
{"title": "Sample 1", "description": "", "hold_date": null, "keywords": []}
// Canonical
{"title": "Sample 1"}
```

This **does not apply at the element level inside `ordered` arrays** (§3.2): removing an empty element would silently shift every later index (e.g., reassigning the contact at `/submission/submitters/0`). Empty elements in `ordered` arrays are a **hard reject** at canonicalization. A JSON Patch `replace` with `value: null` is permitted at the patch level but applying it removes the target — `null` cannot survive a round trip.

## 3. Array Rules

Array ordering is the highest-stakes decision here. RFC 8785 preserves array order verbatim; we layer **per-path classification** on top because JSON Pointer (RFC 6901) addresses elements by integer index. Once a patch references `/samples/3/attributes/2`, that index must resolve to the same logical element under every future canonicalization of the chain. **An array's mode is frozen at `canonical_version`** — even adding a tiebreaker is breaking. The registry lives in `schema/canon/array-modes.yml`.

### 3.1 The Three Modes

#### ordered

Order is semantic. Elements emit in input order; the canonicalizer never touches position. Insertion uses an explicit index — never JSON Patch's `-` token. Empty elements are rejected (§2.5).

Paths: `/submission/submitters` (`[0]` = contact); `/sequences/entries` (flatfile order); `/sequences/entries/*/source_features`; `/sequences/entries/*/comments`; `/experiments/*/spot_descriptor/reads` (by `read_index`); `/experiments/*/processing`, `/analyses/*/processing` (step chain); `/runs/*/files`, `/analyses/*/files` (R1/R2 positional); `/project/publications/*/{authors,consortiums}` (byline); `/provenance/gff/pragmas`; any `qualifiers[<key>]` list (INSDC).

#### keyed

Order is by a stable key tuple. Tuple components are normalized via §2.2 single-line rules **on both sides of every comparison**, then JCS-serialized as a JSON array, then byte-compared as UTF-8. (RFC 8785's UTF-16 ordering applies only to object keys, not to keyed-array tuples; UTF-8 is chosen for portability with content-addressing.) Missing or empty components coerce to `''` (key absent, or value dropped under §2.5); `‖ ''` in the table is shorthand for this.

| Path | Key tuple |
|---|---|
| `/samples` | `(alias,)` |
| `/relations` | `(type, target.db ‖ '', target.id ‖ '', target.url ‖ '')` |
| `/**/attributes` | `(name, unit ‖ '')` |
| `/project/publications` | `(doi ‖ '', pubmed_id ‖ '', title ‖ '')` |
| `/project/grants` | `(id ‖ '', title ‖ '', agency ‖ '')` |
| `/access_control/dacs` | `(alias ‖ '', accession ‖ '')` |
| `/access_control/dacs/*/contacts` | `(email ‖ '', last ‖ '', first ‖ '')` |
| `/datasets` | `(alias ‖ '', accession ‖ '')` |

`/samples` is keyed (not bag) because Spike 0.1 confirmed every production BS record assigns an `alias` and a 10K-sample bag-sort would dominate every diff. Records violating the invariant (no `alias`) are rejected at ingest, not silently bagged.

**Collisions** (identical tuples) are permitted; the canonicalizer warns and sub-sorts by `sha256(canonical_json(element))`. Legacy duplicates must not be rejected.

#### bag

No natural key. Sort by `sha256(canonical_json(element))` ascending (hex, byte order). Applies to `/experiments`, `/runs`, `/analyses`, `/features`, scalar bags (`/project/{study_types,keywords,locus_tag_prefix,target/data_types}`, `/datasets/*/dataset_types`, `/sequences/entries/*/structured_comments`).

A bag element is identified entirely by content. **Field-level patches into bags are normatively forbidden**:

1. The diff generator MUST emit whole-element `remove` + `add` for any change inside a bag; MUST NOT emit a patch whose `path` traverses a bag array beyond the array index.
2. The patch verifier MUST reject any incoming patch whose `path` or `from` descends into a bag (more segments after the integer index).

Unclassified paths default to bag; the registry SHOULD list all production paths explicitly (see §3.4).

**Performance.** Implementations MUST memoize each element's canonical bytes across the sort comparator so each element is canonicalized + hashed once per pass, not O(log N) times. For large bags, a streaming variant hashes as elements are read, buffers `(hash, element_bytes)`, sorts by hash, emits.

### 3.2 Empty Elements

After leaf canonicalization, an element reducing to `{}`, `[]`, `""`, or `null` is removed from its parent array before sort/hash for `keyed` and `bag`. For `ordered` arrays, an empty element is a **hard reject** (removing would shift downstream indices). Applied recursively bottom-up.

### 3.3 Why Keyed Over Ordered for Attributes

Spike 0.1's noise measurement on the BS cohort: ~60% of cross-version diff lines were positional churn from curators reordering `geo_loc_name` / `collection_date` / `lat_lon` triples with no semantic order. Keying by `(name, unit)` collapsed that to zero. Generalizes to `/relations`, `/publications`, `/grants`. **Rule of thumb:** keyed if a stable identifying tuple exists; bag otherwise; ordered only with documented justification.

### 3.4 Frozen-Once-Set

Modifying or removing a classification is breaking. **Adding a path is also breaking if any prior canonicalization observed that path under the implicit bag default** — re-classifying it to keyed or ordered re-sorts the same input to different bytes. Only adding paths that do not appear in any prior canonicalized data is backward-compatible without a version bump. CI enforces via the corpus-hash check.

## 4. Volatile Field Stripping

### 4.1 Definition

"Volatile" = system-generated metadata that changes between regenerations without reflecting curator or data change. Distinct from metadata generally: curator-supplied dates, archive-managed contacts, and submitter assertions are metadata but not volatile.

The test is **volatility, not authorship**. A field being archive-assigned rather than curator-written does not make it volatile — an accession is archive-assigned and perfectly stable, so it is durable state and belongs in the diff (v2; see Version History). Ask "would regenerating this record from the same source produce a different value?", not "who wrote it?".

### 4.2 Strip-on-Diff, Not Strip-on-Storage

Canonical form **retains** volatile fields for stored snapshots (audit + regeneration verification). They are removed only when canonicalizing **for diffing**:

```
canonicalize(record, *, for_diff: bool = False)
```

`for_diff=True` applies the volatile-field registry as a pre-pass: each registered JSON Pointer and its descendants is removed before JCS serialization. Storage uses `False`; chain replay uses `True` on both sides of every step.

**Stored state must itself be canonical.** Diff emits array indices into the canonical ordering, while apply is pure RFC 6902 against whatever it is handed. A chain whose stored state is not canonical therefore has ops naming the wrong element of a `keyed` or `bag` array — silently, and only where the input order happened to differ from the key order. Anything written as a root snapshot (`{"op":"add","path":""}`) MUST be canonicalized with `for_diff=False` first; incremental patches preserve the property inductively.

### 4.2.1 Diff Cost

Aligning two arrays by similarity is quadratic, and a BioSample submission carries up to 10^5 `/samples` elements. It is also unnecessary: a `keyed` array declares its identity in the registry and canonicalization has already sorted both sides by it, so the alignment is known before the diff starts. Implementations SHOULD merge-join keyed arrays on the key and recurse only into matched pairs, falling back to similarity alignment for `ordered` / `bag` arrays, which are small by construction. Measured on this implementation at 8,000 samples: 181 s before, 5.9 s after.

### 4.3 Stripped Paths (`ddbj-canon/v2`, `for_diff=True`)

- `/provenance` (subtree).
- `/schema_version`.
- `/last_update`, `/access`, `/publication_date` (BS-derived mirrors).

Each one differs between two regenerations of the same source. That is the whole membership rule.

### 4.4 Not Stripped (Real Signal)

All `accession` fields at any depth — project, samples, experiments, runs, analyses, sequences entries, datasets, assembly, access_control policy/dac (v2; stripped in v1). Archive-assigned but stable: issuance is a change and must appear as one.

`/submission/hold_date` (embargo); `/submission/submitters/*` (curator content; `submitters[0]` = contact); `/project/publications/*/date`, `/runs/*/run_date`, `/analyses/*/analysis_date`, `/submission/st26/{filing_date,production_date}`; `/access_control/*` content. The line: **regeneration artifacts out; durable state in, whoever assigned it.**

### 4.4.1 Replay and Root Snapshots

An `add` or `replace` at path `""` replaces the whole document (RFC 6902 §4.1/§4.3), so no operation before it can affect the result. Replay MUST therefore be able to start at the most recent such operation rather than at `{}`.

This is not only an optimisation. A patch that cannot be applied — a corrupt body, or ops that no longer fit the state at that point — otherwise stops replay permanently, including for every later operation that would have made it irrelevant. An implementation that always walks from `{}` leaves such a chain readable only from a cache, which is the same as saying the chain no longer explains the record.

Implementations SHOULD record the property when the patch is written rather than deriving it during replay: deciding it requires parsing, and parsing every patch to find out which to skip costs what skipping them saves. An unparseable patch MUST NOT be treated as a snapshot.

A snapshot does not repair the past: a point-in-time read behind the damage still fails, and MUST, because that state genuinely cannot be reconstructed.

### 4.5 Effect on JSON Pointers

Stripped paths do not appear in diff input, so generated patches cannot reference them. Verifiers MUST reject any stored patch whose `path` resolves into a stripped subtree. Array-sort guarantees in §3 still hold (stripping precedes sort-key resolution).

### 4.6 Backwards Compatibility of the Strip List

Finer than "add safe, remove unsafe":

- **Adding** a strip path is safe (no version bump) iff no live patch references that path. Still updates golden vectors and requires curation sign-off — hiding a field from diffs hides change events.
- **Adding** when a live patch references the path requires a version bump: the patch becomes unreplayable. Scan history first; v2 + chain rebase/collapse.
- **Removing** always requires a version bump (prior chains need retroactive re-diffing).

The strip list is policy, not implementation detail.

## 5. Conformance Tests

### 5.1 Categories

- **Idempotence + round-trip.** `canon(canon(x)) == canon(x)` and `canon(parse(serialize(canon(x)))) == canon(x)` on every fixture and randomized inputs.
- **Key-order independence.** `canon({a:1,b:2}) == canon({b:2,a:1})`.
- **Whitespace.** Single-line vs multi-line, including U+00A0, U+3000, U+200B, plus the NFC-vs-NFKC asymmetry of §2.2.
- **Unicode NFC.** NFD → NFC; `café` hashes identically across forms; `ＤＤＢＪ` preserved.
- **Sequence streaming.** 1 GiB synthetic sequence canonicalizes with O(1) auxiliary memory (RSS-bounded test).
- **Null/empty.** `{a:null,b:"",c:[],d:{}}` → `{}`; `{a:0,b:false}` preserved. Empty `ordered` element → REJECT.
- **Array modes.** One fixture per mode: ordered (reorder fails equality), keyed (reorder identical; tiebreak exercised), bag (reorder identical; whole-element patch enforcement verified).
- **Volatile stripping.** `for_diff=true` drops `/provenance`, `/schema_version` and the BS-derived mirrors; `for_diff=false` retains. Both idempotent. `accession` survives both (v2) — a fixture pins that an accession-only delta yields a non-empty patch.
- **Patch canon (§1.6).** Idempotent; key reorder preserves output; ops reorder does not.
- **`measure.py` equivalence (Phase-1 gate).** Spike 0.1 subset canonicalized by `tmp/data-migration/spike-0-1/measure.py` yields the same diff set as `ddbj-canon/v1`. Phase 1 must land this before §5.3's corpus claim.

### 5.2 Golden Fixtures

At `spec/fixtures/canonical_json/`, one directory per fixture (`input.json`, `expected.canon`, `expected.sha256`). Minimum: `project_minimal`, `sample_migs` (14-entry `/attributes` shuffled), `relations_graph`, `record_multi_sample`, `sequences_entry_ordered`, `sequence_streaming_large` (100 MiB, gated).

### 5.3 Acceptance

- All conformance categories pass.
- At least one fixture per v3 top-level array (`samples`, `experiments`, `runs`, `analyses`, `sequences.entries`, `features`, `datasets`, `relations`).
- §5.1 `measure.py` equivalence passes on the Spike 0.1 cohort. `tmp/data-migration/spike-0-1/replay.sh` enforces; divergence blocks merge.
- `canonical_version` recorded in each fixture's `expected.canon` header; mismatch is a hard error.

### 5.4 CI

- `bundle exec rspec spec/canonical_json/` on every PR, gated in `api.yml`.
- Fixtures regenerated only via `bin/canon-update-fixtures`, which refuses to run unless `CANONICAL_VERSION` env matches the spec constant.
- Changes to normalization, single-line paths, array-mode registries, or the volatile-strip set require: (a) version bump, (b) migration note in `docs/canonical-json.md`, (c) replay-test coverage. `rake canon:guard` enforces.
- RFC 8785 reference vectors vendored at `spec/fixtures/canonical_json/jcs/` and run unmodified — any drift is a regression.

## 6. Appendix: Field Classification Table

Legend — string classes (§2.2): **SL** single-line, **ML** multi-line, **SEQ** sequence. Numbers: **INT**, **FLT**. Array modes (§3): **O** ordered, **K** keyed, **B** bag. **Vol** = stripped under `for_diff=true`. Defaults: any string-typed field not listed is multi-line; any unlisted array is bag (treat as bug — registry SHOULD list explicitly, see §3.4).

### Top-Level

| Path | Mode / Type | Notes |
|---|---|---|
| `/schema_version`, `/provenance` (subtree) | — | **Vol** |
| `/submission`, `/project`, `/sequences`, `/assembly`, `/access_control` | object | — |
| `/samples` | K `(alias,)` | — |
| `/experiments`, `/runs`, `/analyses`, `/features` | B | — |
| `/datasets`, `/relations` | K | — |

### Submission

| Path | Mode / Type | Notes |
|---|---|---|
| `/submission/submitters` | O | `[0]` = contact |
| `/submission/submitters/*/{first,last,email}` | SL | — |
| `/submission/submitters/*/organizations` | B | — |
| `/submission/hold_date`, `/submission/st26/{filing_date,production_date}` | SL | ISO 8601 |
| `/submission/comments/*` | ML | open question §7.5 |
| `/submission/st26/invention_titles` | K `(language_code,)` | — |
| `/submission/attributes` | K `(name, unit ‖ '')` | — |

### Project

| Path | Mode / Type | Notes |
|---|---|---|
| `/project/accession` | SL | — |
| `/project/{name,project_type,umbrella_subtype}` | SL | — |
| `/project/{title,description}` | ML | — |
| `/project/{locus_tag_prefix,keywords,study_types}/*`, `/project/target/data_types/*` | SL in B | — |
| `/project/relevance/*` | SL | map values |
| `/project/publications` | K `(doi, pubmed_id, title)` | — |
| `/project/publications/*/authors` | O | byline |
| `/project/publications/*/{pubmed_id,doi,journal,volume,issue,pages_from,pages_to,date}` | SL | — |
| `/project/publications/*/title` | ML | — |
| `/project/grants` | K `(id, title, agency)` | — |

### Samples

| Path | Mode / Type | Notes |
|---|---|---|
| `/samples/*/accession` | SL | — |
| `/samples/*/{alias,title,package,donor_id,sample_group_type}` | SL | — |
| `/samples/*/description` | ML | — |
| `/samples/*/organism/{name,common_name}` | SL | — |
| `/samples/*/organism/taxonomy_id` | INT | NCBI taxid |
| `/samples/*/attributes` | K `(name, unit ‖ '')` | — |
| `/samples/*/attributes/*/{name,unit}` | SL | — |
| `/samples/*/attributes/*/value` | ML | open question §7.2 |

### Experiments / Runs / Analyses

| Path | Mode / Type | Notes |
|---|---|---|
| `/{experiments,runs,analyses}/*/accession` | SL | — |
| `/experiments/*/{alias,title}`, `/runs/*/{alias,title,run_date,data_type}`, `/analyses/*/{alias,title,analysis_type,analysis_date,data_type}` | SL | — |
| `/experiments/*/description` | ML | — |
| `/experiments/*/library/nominal_length` | INT | — |
| `/experiments/*/library/nominal_sdev` | FLT | — |
| `/experiments/*/library/construction_protocol`, `/experiments/*/platform/array_description` | ML | — |
| `/experiments/*/library/*`, `/experiments/*/platform/*` (other) | SL | CV |
| `/experiments/*/spot_descriptor/reads` | O | `read_index` |
| `/{experiments,analyses}/*/processing` | O | step chain |
| `/experiments/*/targeted_loci/*` | SL in B | — |
| `/{runs,analyses}/*/files` | O | R1/R2 positional |
| `/{runs,analyses}/*/files/*/*` | SL | filename, checksum |

### Sequences / Features / Assembly

| Path | Mode / Type | Notes |
|---|---|---|
| `/sequences/seq_prefix` | SL | — |
| `/sequences/entries` | O | flatfile order |
| `/sequences/entries/*/accession`, `/assembly/accession` | SL | — |
| `/sequences/entries/*/{alias,name,type,topology,division}`, `/assembly/{alias,name,assembly_level,genome_representation}` | SL | — |
| `/sequences/entries/*/sequence` | **SEQ** | alphabet `[acgtn]` post-normalize |
| `/sequences/entries/*/comments/*`, `/assembly/{title,description}` | ML | — |
| `/sequences/entries/*/source_features` | O | — |
| `/sequences/entries/*/source_features/*/qualifiers/<key>`, `/features/*/qualifiers/<key>` | O | per-key positional |
| `/sequences/entries/*/structured_comments` | B | — |
| `/features/*/{location,score,phase}` | SL / FLT / INT | — |
| `/features/*/parent_ids/*` | SL in B | — |
| `/assembly/attributes` | K `(name, unit ‖ '')` | — |

### Datasets / Access Control / Relations / Provenance

| Path | Mode / Type | Notes |
|---|---|---|
| `/datasets/*/accession`, `/access_control/policy/accession` | SL | — |
| `/datasets/*/{alias,name}`, `/access_control/policy/policy_url` | SL | — |
| `/datasets/*/description`, `/access_control/policy/policy_text` | ML | — |
| `/datasets/*/dataset_types/*` | SL in B | — |
| `/datasets/*/attributes` | K | — |
| `/access_control/dacs` | K `(alias, accession ‖ '')` | — |
| `/access_control/dacs/*/contacts` | K `(email, last, first)` | — |
| `/relations/*/{type,label,source,target.*}` | SL | — |
| `/relations/*/properties/*` | SL | map values |
| `/provenance/**` | — | **Vol** (entire subtree, includes `gff/pragmas` O ordering preserved within snapshot) |

## 7. Open Questions (resolve before first production freeze)

1. **Sequence alphabet.** §2.2 fixes `[acgtn]`. Sample a GB-scale assembly to confirm no curator data carries IUPAC ambiguity codes (R/Y/W/S/K/M/…) that must be preserved. If present, widen *before* freeze.
2. **EAV `value` line-discipline.** Lat/lon strings like `"31.45N 131.00 E"` preserve internal spacing under multi-line. Confirm with curators or sub-type lat/lon/date/taxid EAV values.
3. **Cross-language hash stability.** Bag-sort by `sha256(canonical_json(element))` is deterministic given identical canonicalization. Ruby and Python (and TS, if used) JCS implementations must agree byte-for-byte on sub-elements. Cross-language test harness against vendored JCS vectors must land before freeze.
4. **`pubmed_id` int/string boundary.** §2.3 requires string serialization; schema currently loose. Lock the rule and string-type the schema, or accept that the schema decision forces a canon revision.
5. **`/submission/comments` ordering.** Survey says "free-form notes" → bag, but `entries[*].comments` (similar) is ordered. Curator-side decision; defaulting to bag now means re-sorting on a later classification (§3.4).
6. **"Starred" placeholder values** (`"*organism"`, `"*env_broad_scale"`). Currently preserved verbatim. Draft markers (strip) or legitimate sentinels (round-trip)? Sweep the BS cohort.
7. **Collision logging surface.** §3.1 keyed collisions emit warnings — destination (Rails logger / SolidQueue job status / admin dashboard) must be specified.
8. **`canonical_version` storage.** Column placement on `submission_updates` and/or `submissions` deferred to `project_db_column_design`.
9. **JCS library selection.** Pick `rfc8785` (Ruby) and `canonicalize` / `@truestamp/canonify` (TS). Vendoring strategy is a Phase 2 freeze blocker.

## 8. Editorial Notes

- **M1**: §2.2 step 5 now uses explicit `U+xxxx` notation (prior rendering had literal control bytes that broke Markdown).
- **M2**: §2.3 cites the ES262 `n ≥ 21` cutoff. `1e10 → 10000000000` is correct below the cutoff; above it, `1e+21`.
- **M3**: `/_meta` reference removed — undefined, not used in v3.
- **M4**: §4.6 distinguishes safe additions (no live patch references the path) from version-bumping additions (an active chain references it). Removal always bumps.
- **M5**: Status now gates first freeze on all §7 Open Questions being resolved; "frozen-on-use" semantics unchanged, but immediate v2 is prevented.
- **M6**: §1.6 specifies canonicalization of the JSON Patch document itself, ordered `ops` array intact.
