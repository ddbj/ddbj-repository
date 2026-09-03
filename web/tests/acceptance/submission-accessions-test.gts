import { module, test } from 'qunit';
import { visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

const now = '2025-01-01T00:00:00.000Z';

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

    // One table for three databases: what a record states beyond its
    // number travels as labelled facts, so the table does not grow a
    // column the other two leave empty.
    assert.dom('[data-test-accessions]').includesText('Organism');
    assert.dom('[data-test-accessions]').includesText('MIMS.me.water.6.0');

    // Where DDBJ has got to with each row — the difference between this
    // list and the one a reviewer is shown.
    assert.dom('[data-test-accessions]').includesText('public');
  });
});
