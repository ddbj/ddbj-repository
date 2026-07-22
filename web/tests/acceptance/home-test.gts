import { module, test } from 'qunit';
import { visit, click, fillIn, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

const now = '2025-01-01T00:00:00.000Z';

module('Acceptance | home', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('lists submission requests across databases', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json(
          [
            {
              id: 7,
              db: 'biosample',
              status: 'applied',
              created_at: now,
              submission_id: 42,
              source_id: 'SSUB000123',
              first_accession: 'SAMD00000001',
              accession_count: 3,
              has_unread_curator_message: true,
            },
            {
              id: 3,
              db: 'bioproject',
              status: 'validating',
              created_at: now,
              submission_id: null,
              source_id: null,
              first_accession: null,
              accession_count: 0,
              has_unread_curator_message: false,
            },
          ],
          {
            headers: { 'Total-Pages': '1' },
          },
        );
      }),
    );

    await visit('/');

    assert.strictEqual(currentURL(), '/');
    assert.dom('h1').hasText('Submission Requests');
    assert.dom('tbody tr').exists({ count: 2 });

    const firstRow = 'tbody tr:nth-child(1)';
    assert.dom(`${firstRow} td:nth-child(1)`).includesText('#7');
    assert.dom(`${firstRow} td:nth-child(1) .badge.text-bg-warning`).hasText('New message');
    assert.dom(`${firstRow} td:nth-child(2)`).hasText('BioSample');
    assert.dom(`${firstRow} td:nth-child(3) .badge`).hasText('applied');
    assert.dom(`${firstRow} td:nth-child(4)`).hasText('SSUB000123'); // Source ID
    assert.dom(`${firstRow} td:nth-child(5)`).includesText('SAMD00000001'); // Accession
    assert.dom(`${firstRow} td:nth-child(5)`).includesText('(3)'); // first + total count

    const secondRow = 'tbody tr:nth-child(2)';
    assert.dom(`${secondRow} td:nth-child(1)`).hasText('#3');
    assert.dom(`${secondRow} td:nth-child(1) .badge.text-bg-warning`).doesNotExist();
    assert.dom(`${secondRow} td:nth-child(2)`).hasText('BioProject');
    assert.dom(`${secondRow} td:nth-child(3) .badge`).hasText('validating');
    assert.dom(`${secondRow} td:nth-child(4)`).hasText('-'); // no source id
    assert.dom(`${secondRow} td:nth-child(5)`).hasText('-'); // no accession
  });

  test('empty state links to /new', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json([], {
          headers: { 'Total-Pages': '1' },
        });
      }),
    );

    await visit('/');

    assert.dom('table').doesNotExist();
    assert.dom('a[href="/web/new"]').exists({ count: 2 });
  });

  test('"New Submission" navigates to /new with database picker', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json([], {
          headers: { 'Total-Pages': '1' },
        });
      }),
    );

    await visit('/');
    await click('.btn-primary');

    assert.strictEqual(currentURL(), '/new');
    assert.dom('h1').hasText('New Submission');
    assert.dom('a[href="/web/st26/requests/new"]').exists();
    assert.dom('a[href="/web/bioproject/requests/new"]').exists();
    assert.dom('a[href="/web/biosample/requests/new"]').exists();
  });

  test('unchecking a database facet and submitting narrows the list', async function (assert) {
    const rows: components['schemas']['SubmissionRequestSummary'][] = [
      {
        id: 7,
        db: 'biosample',
        status: 'applied',
        created_at: now,
        submission_id: 42,
        source_id: 'SSUB000123',
        first_accession: 'SAMD00000001',
        accession_count: 3,
        has_unread_curator_message: false,
      },
      {
        id: 3,
        db: 'bioproject',
        status: 'validating',
        created_at: now,
        submission_id: null,
        source_id: null,
        first_accession: null,
        accession_count: 0,
        has_unread_curator_message: false,
      },
    ];

    worker.use(
      http.get('/submission_requests', ({ request, response }) => {
        const dbs = new URL(request.url).searchParams.getAll('db[]');
        const filtered = dbs.length ? rows.filter((r) => dbs.includes(r.db)) : rows;

        return response(200).json(filtered, { headers: { 'Total-Pages': '1' } });
      }),
    );

    await visit('/');

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
    assert.dom('tbody tr td:nth-child(2)').hasText('BioSample');

    // Clear filters restores the full list with every box checked again.
    // (`:not(.p-0)` distinguishes it from the Select all / Deselect all links.)
    await click('.btn-link:not(.p-0)');
    assert.dom('#db-bioproject').isChecked();
    assert.dom('tbody tr').exists({ count: 2 });
  });

  test('the Accession search sends an accession param on submit', async function (assert) {
    const rows: components['schemas']['SubmissionRequestSummary'][] = [
      {
        id: 7,
        db: 'biosample',
        status: 'applied',
        created_at: now,
        submission_id: 42,
        source_id: null,
        first_accession: 'SAMD00000001',
        accession_count: 1,
        has_unread_curator_message: false,
      },
      {
        id: 3,
        db: 'bioproject',
        status: 'validating',
        created_at: now,
        submission_id: null,
        source_id: null,
        first_accession: null,
        accession_count: 0,
        has_unread_curator_message: false,
      },
    ];

    worker.use(
      http.get('/submission_requests', ({ request, response }) => {
        const accession = new URL(request.url).searchParams.get('accession');
        const filtered = accession ? rows.filter((r) => (r.first_accession ?? '').startsWith(accession)) : rows;

        return response(200).json(filtered, { headers: { 'Total-Pages': '1' } });
      }),
    );

    await visit('/');
    assert.dom('tbody tr').exists({ count: 2 });

    await fillIn('#accession-filter', 'SAMD');
    await click('form button[type="submit"]');

    assert.dom('tbody tr').exists({ count: 1 });
    assert.dom('tbody tr td:nth-child(5)').includesText('SAMD00000001');
  });

  test('Select all / Deselect all toggle a whole facet', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json(
          [
            {
              id: 1,
              db: 'st26',
              status: 'applied',
              created_at: now,
              submission_id: 1,
              source_id: null,
              first_accession: null,
              accession_count: 0,
              has_unread_curator_message: false,
            },
          ],
          { headers: { 'Total-Pages': '1' } },
        );
      }),
    );

    await visit('/');

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
