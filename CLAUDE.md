# CLAUDE.md

## Project Overview

DDBJ Repository — a submission management system for DDBJ (DNA Data Bank of Japan). Users submit sequence data (ST.26 XML for patents, DDBJ Record JSON for general), which is validated, assigned accession numbers, and converted to DDBJ flatfiles.

## Repository Structure

Monorepo with Rails backend at the root and Ember.js frontend in `web/`.

```
app/              Rails application
web/              Ember.js frontend
schema/           OpenAPI schema + canonicalization registries
docker/           SeaweedFS accessory (Kamal runs the entrypoint in production and staging)
test/             Minitest tests
data/             Qualifier/feature reference data
doc/              Format specifications (canonical JSON)
```

## Tech Stack

### Backend (Ruby on Rails)

- Ruby (see `.ruby-version`)
- Views: `.json.jb` templates (not Jbuilder)
- Background jobs: SolidQueue (`SOLID_QUEUE_IN_PUMA=true`)
- Object storage: SeaweedFS (S3-compatible, via ActiveStorage)
- JSON parsing: Oj (SAJ for small files, ScHandler streaming for large files)
- Deploy: Kamal (`bin/kamal deploy -d staging`)

### Frontend (Ember.js)

- Directory: `web/`
- Package manager: pnpm
- Build: Vite + Embroider
- Templates: `.gts`/`.gjs` only (strict mode, no `.hbs`)
- TypeScript with Glint
- Testing: QUnit + ember-qunit + MSW + openapi-msw
- Linting: ESLint, Prettier, StyleLint, ember-template-lint

## Development Commands

```sh
bin/setup          # Initial setup
bin/dev            # Start Rails and Ember (SeaweedFS and Keycloak run outside — see README)
bin/rails test:all # Run backend tests INCLUDING test/system (`test` alone skips them)
cd web && pnpm test  # Run frontend tests
cd web && pnpm lint  # Run frontend linters
```

### Testing

Anything a person does through a screen belongs in `test/system` — a
Capybara test that visits the page and presses the control. Integration
tests address routes directly and are therefore blind to everything
between the screen and the request; several bugs have shipped past a
green integration suite because the endpoint was right and the control
that reached it was not.

- `test/system` — user-perspective. `rack_test` by default; subclass
  `JavaScriptSystemTestCase` for screens whose behaviour is Turbo /
  Stimulus (runs it in process via `capybara-simulated`, no browser).
- `test/integration` — the JSON API, and server-side rules with no screen.

The admin integration tests predate this split and still address screens
directly; migrate them as those screens are touched rather than in one
sweep. A system test that covers the same ground replaces the
integration one — leaving both means two suites drifting, and the
integration half keeps encoding requests no browser makes.

Address controls by their accessible name (`aria-label` counts —
`Capybara.enable_aria_label` is on) and sections by `data-test-*`. CSS
classes are the framework's, not ours, and matching on them tests
nothing a user can see.

## CI

Three workflows on push:
- **API** (`api.yml`): `bin/rails test:all`, `brakeman`, `rubocop`
- **Web** (`web.yml`): `pnpm lint`, `pnpm test`, and a `Schema` job that
  regenerates `openapi.d.ts` and fails if it differs from the committed one
- **Canon** (`canon.yml`): the canonicalization gates — see below

Canon overlaps `api.yml` on the Ruby tests by design; what only it does is
run `canon:fields_check` / `canon:registry_completeness`, and install
Python `rfc8785` so `cross_lang_jcs_test.rb` actually runs instead of
skipping. Keeping the Python toolchain out of the API test job is the
reason it is a separate workflow.

## Key Architecture

### DDBJRecord Parsing (Streaming)

Large DDBJ Record JSON files (10+ GB genome assemblies) are parsed via `DDBJRecord::StreamingParser`:

- Uses `Oj.sc_parse` (ScHandler) for true streaming entry enumeration
- `EntryStreamHandler` intercepts the `sequences.entries` array and yields entries one at a time
- First pass collects metadata + features (entries discarded); subsequent passes stream entries
- Memory proportional to the largest single entry, not total file size

For small files, the same code path works — `sc_parse` handles both minified and pretty-printed JSON.

### Flatfile Generation

- `Flatfile::Root` — original in-memory renderer (loads all entries)
- `Flatfile::StreamingRenderer` — entry-by-entry renderer for large files, reuses the same ERB template
- `Flatfile::TaxIdCache` — lazy-loading taxonomy cache for streaming

#### The LOCUS date

One date, three places that must agree, and one person who owns it.

**`locus_date` is the date printed on the LOCUS line.** It is chosen by whoever
performs the publication — for ST.26 that is DDBJ's own operator running
`submission-bulk-st26 --date`, not the submitter and not this server, which is
why neither the JPO XML nor an apply-time clock can supply it.

It lives in three places, and they hold the same value by construction:

| Place | Role |
|---|---|
| the record's `sequences.entries[].locus_date` | how it arrives, and what the archived record states |
| `entries.locus_date` | the queryable copy — API, admin, and where a redate is written |
| the flatfile's LOCUS line | rendered from the record field the renderer is handed |

`ApplySubmissionRequestJob` takes the date from the record and writes both,
falling back to the apply date only when the record names none.
`RegenerateSubmissionFlatfilesJob` renders from the column and writes the date to
the entries the run names — so redating some entries of a submission is what the
Regenerate screen's accession list is for. The file is the submission's, so the
whole of it is rewritten either way; the list decides only whose date moves.

A run that names no date renders every entry from the column and **refuses** if
the column and the record disagree, rather than publishing the column's value.
That is the guard the 62-entry incident cost.

This was three different dates until 2026-08: the column held the apply date,
the record field was called `last_updated` and held the operator's date, and the
flatfile printed the record's. Regeneration renders from the column, so any
regeneration silently pulled published LOCUS dates back to the apply date —
which is what happened to 62 entries while fixing PATENT-386. Records written
before the rename still say `last_updated`, and `Builders` reads both keys.

Two consequences of that history:

- The column was put back across the archive on 2026-08-10 — 9,813,674 entries
  over 17,999 submissions, read from each request's record, which no regeneration
  rewrites. `rake locus_date:backfill` did that and has been deleted; its
  premise (an entry still carrying the apply stamp is one nobody has dated) only
  held for records written before the change. If the two ever disagree again the
  guard above is what says so, and it means something wrote the column without
  the record.
- The key rename makes a re-serialised legacy record differ from its stored
  blob, so `changed?` is true for every one of them. The first regeneration of
  such a submission therefore rewrites the record and reports nothing skipped;
  that is the rename passing through, not a substantive change.

### Submission Pipeline (`ApplySubmissionRequestJob`)

Two-pass streaming:
1. Collect entry IDs and NA/AA classification → allocate accessions
2. Stream entries → write JSON (StreamingWriter) + flatfiles (StreamingRenderer) simultaneously

### Canonical JSON (`ddbj-canon`)

`doc/canonical-json.md` is the wire-format spec — deterministic byte-identical
serialization of a v3 record, which is what makes SHAs content-addressable and
RFC 6902 patch chains replayable. `DDBJRecord::Canonicalizer` implements it;
`schema/canon/array-modes.yml` and `v3-fields.yml` are the registries it reads.

The spec is versioned (`Canonicalizer::VERSION`, currently `ddbj-canon/v2`) and
frozen on first use: changing a sort rule, the strip list, or string
normalization means a version bump plus a migration for records already
written. `submissions.canonical_version` records which version a record was
written under, so cite section numbers from the doc when touching any of this
rather than inferring the rule from the code.

### Result Codes

One flat `TRD_R` series over both phases, tabulated in README.md. Validation
codes live in `DDBJRecordValidator` and land per finding in
`validation_details.code`; application codes live in
`ApplySubmissionRequestJob::ERROR_CODES` and land once per request in
`submission_requests.error_code`. A new code goes in whichever of those two
places matches its phase, plus a row in the README table.

## Admin Screen Conventions

Four decisions that would otherwise be made again on every screen, and
differently each time. They apply to `app/views/admin/`.

### Empty states are three different things

Reaching zero rows means one of three situations, and they need different
words. `empty_state` renders them.

- **`:first_run`** — nothing has ever been here. Explain what will appear
  and how to start. The only empty state that carries an action.
- **`:filtered`** — rows exist but none match. Recite what is on
  (`active_request_filters` already summarises it) and offer to clear it.
- **`:clear`** — empty is the goal, as in a queue. Say so as an outcome.
  No button: there is nothing to do, and offering one sends somebody
  looking.

### Relative time or absolute, by what the reader is doing

- **`elapsed_time`** (relative, `<time>` with the absolute value in
  `datetime` and `title`) — for "has this been sitting?": queues, list
  columns, anything sorted by age. `stale?` colours it, and in a queue
  where everything is by definition waiting that colour is the only thing
  separating moving from stuck.
- **`format_datetime`** (absolute, minute precision) — for the record:
  logs, audit trails, timestamps quoted in a support thread.
- **Both**, for a run in flight: when it started and whether it is still
  alive are different questions.

Never mix the two in one column, and never print seconds —
`format_datetime` is minute-precision on purpose, and the web client's
`formatDatetime` matches it.

### Filters and page position live in the URL

Never in the session: a filtered view has to survive being sent to
somebody else. Consequences, all of which already hold — keep them:

- The filter form is a GET with no `page` field, so changing a filter
  returns to page 1 rather than to an empty page 3.
- An absent filter param means "everything" (`filter_checkbox_group`
  ticks every box), which is why `Clear` is a link to the bare path.
- Anything that redirects back to a list rebuilds the filter from the
  posted params (`index_filter_params`), not from a client-supplied URL.

### Weight is shown by colour and by how much confirming costs

Four steps. A new action belongs in one of them; if it does not fit, that
is a sign the action needs redesigning rather than a fifth step.

| Weight | Button | Confirmation |
|---|---|---|
| Reversible, one record | `btn-primary` / plain | none |
| Writes, but can be redone | `btn-primary` | state the number affected |
| Irreversible or leaves the building | `btn-warning` | breakdown, count in the label, locked after pressing |
| Everything, and hours of it | `btn-warning` | the above, plus typing a phrase to unlock |

**Red belongs to state, never to a button.** `text-bg-danger` and
`text-danger` say something about the data: it failed, it is overdue, it
is unread and waiting — the queue counts, the due-notice badge, the stale
row. A control is never red, however irreversible: dangerous is amber,
because red already means "look at this" and a button that competes with
that reading wins the attention without carrying the meaning.

Between the two state colours: **red asserts, amber doubts.** A queue row
past its threshold is overdue and that is a fact, so it is red. A
migration run that has reported nothing for an hour might have lost its
worker or might be waiting behind something else — the row cannot tell,
and says so in amber. Where a screen knows, it should say so plainly;
where it does not, the colour should not pretend. (Amber therefore does
double duty — careful on a control, uncertain on a state — which reads
cleanly because a button and a badge are never mistaken for each other.)

Results of anything above the first step belong in a panel that stays
until dismissed, not in a flash.

## File Conventions

- `schema/openapi.yml` — the API contract. `schema/openapi.d.ts` is generated
  from it (`pnpm --dir schema generate`) and is what typechecks the web client,
  so a change to the yml means regenerating and committing both. The `Schema`
  CI job fails if they have drifted.
- `config/seaweedfs.yml` — S3 credentials per environment
- `config/storage.yml` — ActiveStorage config (quotes ERB values to prevent YAML type coercion)
- `docker/seaweedfs/` — entrypoint.sh, s3 config JSON for dev/production
- `data/qual.list` — valid qualifier keys
- `data/kq_note.lst` — qualifier formatting rules (quoted vs unquoted)

## Gotchas

- `mockServiceWorker.js` is generated by MSW. Excluded from Prettier (`.prettierignore`). Regenerate with `npx msw init public --no-save` after MSW version upgrades.
- `active_storage_blobs.service_name` must match the key in `config/storage.yml` (currently `seaweedfs`). After storage migration, update existing records.
- SeaweedFS entrypoint creates the S3 bucket on first boot. If the bucket doesn't exist, uploads fail. Development does not run that entrypoint — the bucket and identity there are created by hand on the shared host instance (README).
- Oj's SAJ parser (`saj_parse`) reads the entire file into memory before parsing. For streaming, use `sc_parse` (ScHandler) which reads via the Reader infrastructure.

## Related Projects

- `ddbj/submission-mss` — MSS Form (similar stack, shares infra patterns)
- `ddbj/submission-bulk-st26` — Bulk ST.26 patent submission pipeline
- `ddbj/ddbj-record-specifications` — DDBJ Record JSON schema (Pydantic/Python)
