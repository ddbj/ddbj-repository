import { module, test } from 'qunit';
import { visit, click, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

const now = '2025-01-01T00:00:00.000Z';

// Every key present, because the contract requires them all — `kind`
// says which of the three collection keys is the populated one.
const emptyNode: components['schemas']['RecordNode'] = {
  kind: 'empty',
  columns: null,
  hidden_columns: null,
  total: null,
  shown: null,
  hidden: 0,
  value: null,
  free_text: false,
  fields: null,
  items: null,
  cells: null,
};

function valueNode(value: string | number): components['schemas']['RecordNode'] {
  return { ...emptyNode, kind: 'value', value };
}

// A BioSample request, which is the case this screen used to get wrong:
// its numbers live on samples, and the list read entries.
const request: components['schemas']['SubmissionRequest'] = {
  id: 1,
  db: 'biosample',
  status: 'applied',
  error_code: null,
  error_message: null,
  created_at: now,
  closed_at: null,
  closable: false,
  sendable: false,
  send_blocked_reason: null,
  recheckable: false,
  processing: false,
  ddbj_record: { filename: 'original.json', url: 'http://example.com/original.json' },
  validation: null,

  progress: {
    step: 'curating',
    failed: false,
    closed: false,
    row_count: 2,
    accessioned_count: 2,
    hold_date: null,
  },
  unread_curator_message_count: 0,
  last_message_at: null,
  sets: [],
  owned: true,
  owner_uid: 'test-user',

  submission: {
    id: 10,
    source_id: 'SSUB015671',
    created_at: now,
    updated_at: now,
    ddbj_record: { filename: 'original.json', url: 'http://example.com/original.json' },
    flatfile_na: null,
    flatfile_aa: null,
    accessions_count: 2,
  },
};

module('Acceptance | a submission’s accessions', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('a BioSample submission lists its samples, with what each record states', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submissions/{id}/accessions', ({ response }) =>
        response(200).json(
          [
            {
              accession: 'SAMD00237947',
              db: 'biosample',
              name: 'station-A-surface',
              details: [
                { label: 'Organism', value: 'marine metagenome' },
                { label: 'Package', value: 'MIMS.me.water.6.0' },
              ],
              status: 'public',
            },
            {
              accession: 'SAMD00237948',
              db: 'biosample',
              name: 'station-A-deep',
              details: [{ label: 'Organism', value: 'marine metagenome' }],
              status: 'private',
            },
          ],
          { headers: { 'Total-Pages': '1', 'Total-Count': '2' } },
        ),
      ),
    );

    await visit('/requests/1/accessions');

    assert.dom('[data-test-accessions]').includesText('SAMD00237947');
    assert.dom('[data-test-accessions]').includesText('station-A-surface');

    // The labels become columns: a submission is one database, so every
    // row states the same facts and they can be read down rather than
    // restated on each line.
    assert.dom('[data-test-accessions] thead').hasText('Accession Name Organism Package Status');
    assert.dom('[data-test-accessions]').includesText('MIMS.me.water.6.0');

    // A record that does not carry one of them leaves the cell empty
    // rather than shifting the row along by a column.
    assert.dom('[data-test-accessions] tbody tr:last-child td:nth-child(4)').hasText('—');

    // Where DDBJ has got to with each row — the difference between this
    // list and the one a reviewer is shown.
    assert.dom('[data-test-accessions]').includesText('public');
  });

  // The screen this change took the ST.26 columns off. They are still
  // here; they arrive as facts and are laid out as columns.
  test('an ST.26 submission still shows its versions and LOCUS dates', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json({ ...request, db: 'st26', submission: { ...request.submission!, source_id: null } }),
      ),

      http.get('/submissions/{id}/accessions', ({ response }) =>
        response(200).json([
          {
            accession: 'QP000001',
            db: 'st26',
            name: 'SEQ|1',
            details: [
              { label: 'Version', value: '1' },
              { label: 'LOCUS date', value: '2026-01-15' },
            ],
            status: 'public',
          },
        ]),
      ),
    );

    await visit('/requests/1/accessions');

    assert.dom('[data-test-accessions] thead').hasText('Accession Name Version LOCUS date Status');
    assert.dom('[data-test-accessions]').includesText('2026-01-15');
  });

  // The record laid out by its own shape. Nothing in the client names a
  // field either — the node says what it is and the renderer draws that.
  test('one accession opens onto what its record says', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submissions/{id}/accessions', ({ response }) =>
        response(200).json([
          {
            accession: 'SAMD00237947',
            db: 'biosample',
            name: 'Sample001',
            details: [],
            status: 'public',
          },
        ]),
      ),

      http.get('/submissions/{id}/accessions/{accession}', ({ response }) =>
        response(200).json({
          accession: 'SAMD00237947',
          db: 'biosample',
          name: 'Sample001',
          details: [],
          status: 'public',
          elided: false,
          unavailable_reason: null,

          sections: [
            { key: 'title', folded: false, precis: null, node: valueNode('Control timepoint A') },

            {
              key: 'organism',
              folded: false,
              precis: null,
              node: {
                ...emptyNode,
                kind: 'fields',
                fields: [
                  { key: 'name', node: valueNode('mouse gut metagenome') },
                  { key: 'taxonomy_id', node: valueNode(410661) },
                ],
              },
            },

            {
              key: 'attributes',
              folded: false,
              precis: null,
              node: {
                ...emptyNode,
                kind: 'table',
                columns: ['name', 'value'],
                hidden_columns: ['unit'],
                total: 2,
                shown: 2,
                cells: [
                  [valueNode('collection_date'), valueNode('2018-04-25')],
                  [valueNode('env_broad_scale'), null],
                ],
              },
            },
          ],
        }),
      ),
    );

    await visit('/requests/1/accessions');
    await click('[data-test-accessions] a');

    assert.strictEqual(currentURL(), '/requests/1/accessions/SAMD00237947');

    // A hash is rows of key and value; an array of same-shaped hashes is
    // a table; anything else is the value.
    assert.dom('[data-test-record]').includesText('Control timepoint A');
    assert.dom('[data-test-record]').includesText('taxonomy_id');
    assert.dom('[data-test-record] table thead').hasText('name value');
    assert.dom('[data-test-record] table tbody').includesText('2018-04-25');

    // Said, never implied: a reader who cannot see that there are more
    // columns will read the ones drawn as all of them.
    assert.dom('[data-test-record-columns-hidden]').includesText('unit');
  });

  // "This subtree is empty" and "this application cannot open that record
  // yet" are different answers, and drawing both as a blank panel tells
  // the second as the first.
  test('a record that cannot be read yet says so', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submissions/{id}/accessions/{accession}', ({ response }) =>
        response(200).json({
          accession: 'ACC_000001',
          db: 'st26',
          name: 'SEQ|1',
          details: [],
          status: 'public',
          elided: false,
          unavailable_reason: 'The record behind this accession is not available to read here yet.',
          sections: [],
        }),
      ),
    );

    await visit('/requests/1/accessions/ACC_000001');

    assert.dom('[data-test-record-unavailable]').includesText('not available to read here yet');
    assert.dom('[data-test-record]').doesNotExist();
  });

  // A BioProject or BioSample submission has no numbers until they are
  // issued, so an empty list is ordinary rather than impossible.
  test('a submission with no accessions yet says so', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),
      http.get('/submissions/{id}/accessions', ({ response }) => response(200).json([])),
    );

    await visit('/requests/1/accessions');

    assert.dom('[data-test-accessions]').doesNotExist();
    assert.dom().includesText('No accessions yet');
  });
});
