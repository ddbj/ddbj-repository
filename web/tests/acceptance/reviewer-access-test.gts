import { module, test } from 'qunit';
import { visit, click, fillIn, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Set = components['schemas']['Set'];
type SharedAccession = components['schemas']['SharedAccession'];

const now = '2025-01-01T00:00:00.000Z';

const mine: SharedAccession = {
  accession: 'PRJDB1234',
  db: 'bioproject',
  name: 'Deep sea metagenome',
  owner_uid: 'test-user',
  owned: true,
};

const theirs: SharedAccession = {
  accession: 'SAMD00000001',
  db: 'biosample',
  name: 'station-A-surface',
  owner_uid: 'colleague',
  owned: false,
};

const set: Set = {
  id: 7,
  name: 'Deep sea study',
  owner_uid: 'test-user',
  owned: true,
  created_at: now,
  member_count: 1,
  invited_count: 0,
  submission_count: 0,
  unread_message_count: 0,
  deletable: true,
  delete_blocked_reason: null,
  members: [],
  submissions: [],
};

module('Acceptance | reviewer view (share link, no login)', function (hooks) {
  setupApplicationTest(hooks);
  // Deliberately no setupAuthentication — reviewers are not logged in.

  test('the shared accessions are the page', async function (assert) {
    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json({
          name: 'Deep sea study',
          expires_at: '2025-02-01T00:00:00.000Z',

          accessions: [
            {
              accession: 'PRJDB1234',
              db: 'bioproject',
              name: 'Deep sea metagenome',
              details: [{ label: 'Type', value: 'primary' }],
            },
          ],
        });
      }),
    );

    await visit('/reviews/secret-token');

    assert.strictEqual(currentURL(), '/reviews/secret-token');
    assert.dom('h1').hasText('Deep sea study');
    assert.dom('[role="note"]').includesText('shared with you');
    assert.dom('[data-test-accessions]').includesText('PRJDB1234');
    assert.dom('[data-test-accessions]').includesText('Deep sea metagenome');

    // Whatever the record carries, in its own words.
    assert.dom('[data-test-accessions]').includesText('Type');
    assert.dom('[data-test-accessions]').includesText('primary');
  });

  test('a link nobody has put anything on says so', async function (assert) {
    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json({
          name: 'Deep sea study',
          expires_at: '2025-02-01T00:00:00.000Z',
          accessions: [],
        });
      }),
    );

    await visit('/reviews/secret-token');

    assert.dom('[data-test-accessions]').doesNotExist();
    assert.dom().includesText('Nothing has been put on this link yet');
  });
});

module('Acceptance | review link (member side)', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('enabling shows the URL, and what is on the link', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.post('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(201).json({
          enabled: true,
          url: 'http://example.com/web/reviews/generated-token',
          expires_at: '2025-01-08T00:00:00.000Z',
          expired: false,
          accessions: [mine, theirs],
        });
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-reviewer-access] input[readonly]').doesNotExist(); // disabled initially

    await click('[data-test-reviewer-access] .btn-primary');

    assert
      .dom('[data-test-reviewer-access] input[readonly]')
      .hasValue('http://example.com/web/reviews/generated-token');

    assert.dom('[data-test-shared]').includesText('PRJDB1234');
    assert.dom('[data-test-shared]').includesText('SAMD00000001');

    // Yours to take off; a colleague's is theirs, and the row says so by
    // not offering the control rather than by disabling it.
    assert.dom('[aria-label="Take PRJDB1234 off the link"]').exists();
    assert.dom('[aria-label="Take SAMD00000001 off the link"]').doesNotExist();
  });

  test('adding accessions puts them on the link', async function (assert) {
    let posted: unknown;
    let shared: SharedAccession[] = [];

    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json({
          enabled: true,
          url: 'http://example.com/web/reviews/generated-token',
          expires_at: '2025-01-08T00:00:00.000Z',
          expired: false,
          accessions: shared,
        });
      }),

      http.post('/sets/{set_id}/reviewer_access/accessions', async ({ request, response }) => {
        posted = await request.json();
        shared = [mine];

        return response(200).json({ added: 1, already_shared: 2 });
      }),
    );

    await visit('/sets/7');

    // One per line or comma-separated — both are what somebody has in
    // hand, so neither is a format to get right.
    await fillIn('[data-test-reviewer-access] textarea', 'PRJDB1234, SAMD00000001\nSAMD00000002');
    await click('[data-test-reviewer-access] button[type="submit"]');

    assert.deepEqual(posted, { accessions: ['PRJDB1234', 'SAMD00000001', 'SAMD00000002'] });
    assert.dom('[data-test-shared]').includesText('PRJDB1234');

    // Both numbers. "1 added" alone leaves somebody who pasted three
    // wondering about the other two.
    assert.dom('.toast').includesText('1 added');
    assert.dom('.toast').includesText('2 already on the link');
  });

  // Revoking takes everything off the link, including accessions the
  // presser may not take off one at a time — so it says how many, and
  // how many are not theirs, before it fires.
  test('revoking says what it costs, and asks first', async function (assert) {
    let revoked = false;

    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json({
          enabled: true,
          url: 'http://example.com/web/reviews/generated-token',
          expires_at: '2025-01-08T00:00:00.000Z',
          expired: false,
          accessions: [mine, theirs],
        });
      }),

      http.delete('/sets/{set_id}/reviewer_access', ({ response }) => {
        revoked = true;

        return response(204).empty();
      }),
    );

    await visit('/sets/7');
    await click('[data-test-reviewer-access] .btn-warning');

    assert.false(revoked, 'nothing has happened yet');
    assert.dom('[data-test-confirm]').includesText('2 accessions');
    assert.dom('[data-test-confirm]').includesText("1 of them other people's");

    await click('[data-test-confirm] .btn-warning');

    assert.true(revoked);
    assert.dom('[data-test-shared]').doesNotExist();
  });

  test('an expired link says so rather than offering a URL that 404s', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json({
          enabled: true,
          url: 'http://example.com/web/reviews/generated-token',
          expires_at: '2025-01-08T00:00:00.000Z',
          expired: true,
          accessions: [mine],
        });
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-reviewer-access] .text-danger').includesText('no longer opens');
  });

  test('an accession that cannot go on is said beside the box it was typed into', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json({
          enabled: true,
          url: 'http://example.com/web/reviews/generated-token',
          expires_at: '2025-01-08T00:00:00.000Z',
          expired: false,
          accessions: [],
        });
      }),

      http.post('/sets/{set_id}/reviewer_access/accessions', ({ response }) => {
        return response(422).json({ error: 'Not in this set: PRJDB9999.' });
      }),
    );

    await visit('/sets/7');

    await fillIn('[data-test-reviewer-access] textarea', 'PRJDB9999');
    await click('[data-test-reviewer-access] button[type="submit"]');

    assert.dom('[data-test-accessions-error]').includesText('PRJDB9999');
  });
});
