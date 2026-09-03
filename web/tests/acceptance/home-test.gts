import { module, test } from 'qunit';
import { visit, click, fillIn, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Summary = components['schemas']['SubmissionRequestSummary'];

const now = '2025-01-01T00:00:00.000Z';

// A row is mostly uninteresting to a given test — spelling out ten fields
// each time buries the one or two that the assertion is actually about.
function summary(attrs: Partial<Summary> & Pick<Summary, 'id' | 'db'>): Summary {
  return {
    status: 'applied',
    created_at: now,
    closed_at: null,
    submission_id: null,
    source_id: null,
    first_accession: null,
    accession_count: 0,
    processing: false,
    sendable: false,
    unread_curator_message_count: 0,
    progress: {
      step: 'applied',
      failed: false,
      closed: false,
      row_count: 0,
      accessioned_count: 0,
      hold_date: null,
    },
    ...attrs,
  };
}

function list(rows: Summary[], counts: { unfinished?: number; finished?: number } = {}) {
  return {
    headers: {
      'Total-Pages': '1',
      'Unfinished-Count': String(counts.unfinished ?? rows.length),
      'Finished-Count': String(counts.finished ?? 0),
    },
  };
}

module('Acceptance | home', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  // The API sorts newest-first and nothing else unless asked, because
  // floating makes the leading sort key move with the data — wrong for
  // anything walking the pages. This screen is the one that wants it, so
  // it has to ask, and dropping the parameter would silently stop the
  // requests waiting on the submitter reaching the top of the list.
  test('asks for the requests waiting on the submitter to be floated', async function (assert) {
    const rows = [summary({ id: 3, db: 'st26' })];

    worker.use(
      http.get('/submission_requests', ({ request, response }) => {
        assert.strictEqual(new URL(request.url).searchParams.get('needs_action_first'), 'true');

        return response(200).json(rows, list(rows));
      }),
    );

    await visit('/');

    assert.dom('tbody tr').exists({ count: 1 });
  });

  // The server answers a database it does not know with 400, and this
  // parameter is bookmarkable: a URL kept from before a rename would
  // otherwise cost the submitter the list rather than the filter.
  test('a database filter the server would refuse is dropped, not sent', async function (assert) {
    const rows = [summary({ id: 3, db: 'st26' })];

    worker.use(
      http.get('/submission_requests', ({ request, response }) => {
        assert.deepEqual(new URL(request.url).searchParams.getAll('db[]'), ['st26']);

        return response(200).json(rows, list(rows));
      }),
    );

    await visit(`/?db=${encodeURIComponent(JSON.stringify(['st26', 'no_such_database']))}`);

    assert.dom('tbody tr').exists({ count: 1 });
  });

  test('lists submission requests across databases', async function (assert) {
    const rows = [
      summary({
        id: 7,
        db: 'biosample',
        submission_id: 42,
        source_id: 'SSUB000123',
        first_accession: 'SAMD00000001',
        accession_count: 3,
        unread_curator_message_count: 1,
        progress: {
          step: 'curating',
          failed: false,
          closed: false,
          row_count: 3,
          accessioned_count: 3,
          hold_date: null,
        },
      }),
      summary({ id: 3, db: 'bioproject', status: 'validating', processing: true }),
    ];

    worker.use(http.get('/submission_requests', ({ response }) => response(200).json(rows, list(rows))));

    await visit('/');

    assert.strictEqual(currentURL(), '/');
    assert.dom('h1').hasText('My submissions');
    assert.dom('tbody tr').exists({ count: 2 });

    const firstRow = 'tbody tr:nth-child(1)';
    assert.dom(`${firstRow} [data-test-id]`).includesText('#7');
    assert.dom(`${firstRow} [data-test-db]`).hasText('BioSample');
    // Where it is now, in the submitter's words rather than the enum's.
    assert.dom(`${firstRow} [data-test-state] .badge`).hasText('A curator has a question');
    assert.dom(`${firstRow} [data-test-source-id]`).hasText('SSUB000123');
    assert.dom(`${firstRow} [data-test-accession]`).includesText('SAMD00000001');
    assert.dom(`${firstRow} [data-test-accession]`).includesText('(3)');

    const secondRow = 'tbody tr:nth-child(2)';
    assert.dom(`${secondRow} [data-test-id]`).hasText('#3');
    assert.dom(`${secondRow} [data-test-db]`).hasText('BioProject');
    assert.dom(`${secondRow} [data-test-state] .badge`).hasText('Being checked');
    assert.dom(`${secondRow} [data-test-source-id]`).hasText('-');
    assert.dom(`${secondRow} [data-test-accession]`).hasText('-');
  });

  // The point of the split: released records must not push the moving
  // ones off the screen.
  test('the phase tabs carry both counts and switch which half is listed', async function (assert) {
    const moving = [summary({ id: 7, db: 'biosample', status: 'ready_to_apply' })];
    const done = [summary({ id: 1, db: 'st26' })];

    worker.use(
      http.get('/submission_requests', ({ request, response }) => {
        const phase = new URL(request.url).searchParams.get('phase');
        const rows = phase === 'finished' ? done : moving;

        return response(200).json(rows, list(rows, { unfinished: 1, finished: 1 }));
      }),
    );

    await visit('/');

    assert.dom('[data-test-phase="unfinished"]').hasClass('active').includesText('1');
    assert.dom('[data-test-phase="finished"]').includesText('1');
    assert.dom('tbody tr [data-test-id]').includesText('#7');

    await click('[data-test-phase="finished"]');

    assert.strictEqual(currentURL(), '/?phase=finished');
    assert.dom('tbody tr [data-test-id]').includesText('#1');
  });

  test('the attention band narrows the list to what is waiting on the submitter', async function (assert) {
    const all = [summary({ id: 7, db: 'biosample', status: 'ready_to_apply' }), summary({ id: 3, db: 'st26' })];

    worker.use(
      http.get('/attention', ({ response }) =>
        response(200).json({
          sets_waiting: 0,
          requests: [{ id: 7, db: 'biosample', source_id: null, reason: 'ready_to_apply' }],
        }),
      ),

      http.get('/submission_requests', ({ request, response }) => {
        const params = new URL(request.url).searchParams;
        const rows = params.get('needs_action') ? all.slice(0, 1) : all;

        return response(200).json(rows, list(all, { unfinished: 2 }));
      }),
    );

    await visit('/');

    assert.dom('.alert').includesText('1 ready to submit');
    assert.dom('tbody tr').exists({ count: 2 });

    await click('.alert a');

    assert.strictEqual(currentURL(), '/?needsAction=true&phase=all');
    assert.dom('tbody tr').exists({ count: 1 });
  });

  test('empty state links to /new', async function (assert) {
    worker.use(http.get('/submission_requests', ({ response }) => response(200).json([], list([]))));

    await visit('/');

    assert.dom('table').doesNotExist();

    // The nav button and the empty state's sentence. Deliberately not a
    // third one beside the heading — two identical controls a few pixels
    // apart only make the reader pick between them.
    assert.dom('a[href="/web/new"]').exists({ count: 2 });
  });

  test('"New Submission" navigates to /new with database picker', async function (assert) {
    worker.use(http.get('/submission_requests', ({ response }) => response(200).json([], list([]))));

    await visit('/');
    // The nav button — the one control that is present on every screen,
    // rather than whichever `.btn-primary` happens to come first.
    await click('nav a[href="/web/new"]');

    assert.strictEqual(currentURL(), '/new');
    assert.dom('h1').hasText('New Submission');
    assert.dom('a[href="/web/st26/requests/new"]').exists();
    assert.dom('a[href="/web/bioproject/requests/new"]').exists();
    assert.dom('a[href="/web/biosample/requests/new"]').exists();
  });

  test('unchecking a database facet and submitting narrows the list', async function (assert) {
    const rows = [
      summary({ id: 7, db: 'biosample', submission_id: 42, source_id: 'SSUB000123' }),
      summary({ id: 3, db: 'bioproject', status: 'validating' }),
    ];

    worker.use(
      http.get('/submission_requests', ({ request, response }) => {
        const dbs = new URL(request.url).searchParams.getAll('db[]');
        const filtered = dbs.length ? rows.filter((r) => dbs.includes(r.db)) : rows;

        return response(200).json(filtered, list(rows));
      }),
    );

    await visit('/');
    await click('.btn-link.p-0'); // reveal the folded-away facets

    // Default: all databases checked, both rows shown.
    assert.dom('tbody tr').exists({ count: 2 });
    assert.dom('#db-bioproject').isChecked();

    // Unchecking is not applied until Filter is pressed (not live).
    await click('#db-bioproject');
    assert.dom('#db-bioproject').isNotChecked();
    assert.dom('tbody tr').exists({ count: 2 });

    // Submit → the facet becomes {st26, biosample}; the bioproject-only
    // request drops out and the box stays unchecked.
    await click('form button[type="submit"]');
    assert.dom('#db-bioproject').isNotChecked();
    assert.dom('tbody tr').exists({ count: 1 });
    assert.dom('tbody tr [data-test-db]').hasText('BioSample');

    // Clear filters restores the full list with every box checked again.
    // (`:not(.p-0)` distinguishes it from the Select all / Deselect all links.)
    await click('form .btn-link:not(.p-0)');
    assert.dom('#db-bioproject').isChecked();
    assert.dom('tbody tr').exists({ count: 2 });
  });

  test('the Accession search sends an accession param on submit', async function (assert) {
    const rows = [
      summary({ id: 7, db: 'biosample', submission_id: 42, first_accession: 'SAMD00000001', accession_count: 1 }),
      summary({ id: 3, db: 'bioproject', status: 'validating' }),
    ];

    worker.use(
      http.get('/submission_requests', ({ request, response }) => {
        const accession = new URL(request.url).searchParams.get('accession');
        const filtered = accession ? rows.filter((r) => (r.first_accession ?? '').startsWith(accession)) : rows;

        return response(200).json(filtered, list(rows));
      }),
    );

    await visit('/');
    await click('.btn-link.p-0');
    assert.dom('tbody tr').exists({ count: 2 });

    await fillIn('#accession-filter', 'SAMD');
    await click('form button[type="submit"]');

    assert.dom('tbody tr').exists({ count: 1 });
    assert.dom('tbody tr [data-test-accession]').includesText('SAMD00000001');
  });

  test('Select all / Deselect all toggle a whole facet', async function (assert) {
    const rows = [summary({ id: 1, db: 'st26', submission_id: 1 })];

    worker.use(http.get('/submission_requests', ({ response }) => response(200).json(rows, list(rows))));

    await visit('/');
    await click('.btn-link.p-0');

    // Default: every database box checked.
    assert.dom('#db-st26').isChecked();

    await click('[data-test-deselect="db"]');
    assert.dom('#db-st26').isNotChecked();
    assert.dom('#db-bioproject').isNotChecked();
    assert.dom('#db-biosample').isNotChecked();

    await click('[data-test-select="db"]');
    assert.dom('#db-st26').isChecked();
    assert.dom('#db-bioproject').isChecked();
    assert.dom('#db-biosample').isChecked();
  });
});
