import { module, test } from 'qunit';
import { visit, click, fillIn, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Set = components['schemas']['Set'];
type SharedAccession = components['schemas']['SharedAccession'];
type SetAccession = components['schemas']['SetAccession'];

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

const candidate: SetAccession = {
  accession: 'PRJDB1234',
  db: 'bioproject',
  name: 'Deep sea metagenome',
  shared: false,
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

// The link, as the member's screen reads it. What is on it is a separate
// request, so this says how much rather than what.
function link(overrides: Partial<components['schemas']['ReviewerAccess']> = {}) {
  return {
    enabled: true,
    url: 'http://example.com/web/reviews/generated-token',
    expires_at: '2025-01-08T00:00:00.000Z',
    expired: false,
    count: 0,
    others: 0,
    ...overrides,
  };
}

module('Acceptance | reviewer view (share link, no login)', function (hooks) {
  setupApplicationTest(hooks);
  // Deliberately no setupAuthentication — reviewers are not logged in.

  test('the shared accessions are the page', async function (assert) {
    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json({ name: 'Deep sea study', expires_at: '2025-02-01T00:00:00.000Z' });
      }),

      http.get('/reviews/{token}/accessions', ({ response }) => {
        return response(200).json([
          {
            accession: 'PRJDB1234',
            db: 'bioproject',
            name: 'Deep sea metagenome',
            details: [{ label: 'Type', value: 'primary' }],
          },
        ]);
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

  // There is no ceiling on what a link carries, so the reviewer's page
  // cannot assume it arrives whole.
  test('a link with more than a page of accessions is paginated', async function (assert) {
    const seen: (string | null)[] = [];

    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json({ name: 'Deep sea study', expires_at: '2025-02-01T00:00:00.000Z' });
      }),

      http.get('/reviews/{token}/accessions', ({ request, response }) => {
        const page = new URL(request.url).searchParams.get('page');

        seen.push(page);

        return response(200).json(
          [
            {
              accession: page === '2' ? 'PRJDB2222' : 'PRJDB1111',
              db: 'bioproject',
              name: 'Deep sea metagenome',
              details: [],
            },
          ],
          { headers: { 'Total-Pages': '3' } },
        );
      }),
    );

    await visit('/reviews/secret-token');

    assert.dom('[data-test-accessions]').includesText('PRJDB1111');
    assert.dom('[data-test-page="2"]').exists();

    await click('[data-test-page="2"] a');

    assert.strictEqual(currentURL(), '/reviews/secret-token?page=2');
    assert.dom('[data-test-accessions]').includesText('PRJDB2222');
    assert.deepEqual(seen, [null, '2']);
  });

  // The same hazard on the reviewer's side, where there is nobody to ask
  // what happened: the accessions resolve through the set on every read.
  test('a reviewer page that has emptied still offers the way back', async function (assert) {
    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json({ name: 'Deep sea study', expires_at: '2025-02-01T00:00:00.000Z' });
      }),

      http.get('/reviews/{token}/accessions', ({ response }) => {
        return response(200).json([], { headers: { 'Total-Pages': '3' } });
      }),
    );

    await visit('/reviews/secret-token?page=2');

    assert.dom('[data-test-accessions]').doesNotExist();
    assert.dom().includesText('Nothing on this page');
    assert.dom().doesNotIncludeText('Nothing has been put on this link yet');
    assert.dom('[data-test-page="1"]').exists('the way back is still there');
  });

  test('a link nobody has put anything on says so', async function (assert) {
    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json({ name: 'Deep sea study', expires_at: '2025-02-01T00:00:00.000Z' });
      }),

      http.get('/reviews/{token}/accessions', ({ response }) => {
        return response(200).json([]);
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
        return response(201).json(link({ count: 2, others: 1 }));
      }),

      http.get('/sets/{set_id}/reviewer_access/accessions', ({ response }) => {
        return response(200).json([mine, theirs]);
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
        return response(200).json(link({ count: shared.length }));
      }),

      http.get('/sets/{set_id}/reviewer_access/accessions', ({ response }) => {
        return response(200).json(shared);
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

  // A range is one entry, not two: it goes to the server as written, and
  // what it names is worked out there against the caller's own work.
  test('a range is sent as one entry', async function (assert) {
    let posted: unknown;

    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json(link());
      }),

      http.post('/sets/{set_id}/reviewer_access/accessions', async ({ request, response }) => {
        posted = await request.json();

        return response(200).json({ added: 50, already_shared: 0 });
      }),
    );

    await visit('/sets/7');

    await fillIn('[data-test-reviewer-access] textarea', 'SAMD00000001-SAMD00000050\nPRJDB1234');
    await click('[data-test-reviewer-access] button[type="submit"]');

    assert.deepEqual(posted, { accessions: ['SAMD00000001-SAMD00000050', 'PRJDB1234'] });
    assert.dom('.toast').includesText('50 added');
  });

  // The list somebody needs when they do not have their numbers to hand,
  // which is the reason a range is writable at all.
  test('your own accessions in the set can be browsed, and shared in one press', async function (assert) {
    let posted: unknown;

    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json(link());
      }),

      http.get('/sets/{set_id}/accessions', ({ response }) => {
        return response(200).json([candidate], { headers: { 'Total-Count': '42', 'Total-Pages': '1' } });
      }),

      http.post('/sets/{set_id}/reviewer_access/accessions', async ({ request, response }) => {
        posted = await request.json();

        return response(200).json({ added: 42, already_shared: 0 });
      }),
    );

    await visit('/sets/7');
    await click('[data-test-browse]');

    assert.dom('[data-test-mine]').includesText('PRJDB1234');
    assert.dom('[data-test-mine]').includesText('42 accessions');

    // One row is the same press as typing its number into the box.
    await click('[aria-label="Put PRJDB1234 on the link"]');

    assert.deepEqual(posted, { accessions: ['PRJDB1234'] });

    posted = undefined;

    // Putting somebody's whole set of work behind an anonymous URL is not
    // a press that should happen by a slip, so it names the number first.
    await click('[data-test-share-all]');

    assert.strictEqual(posted, undefined, 'nothing has happened yet');
    assert.dom('[data-test-confirm]').includesText('42 accessions');

    await click('[data-test-confirm-action]');

    assert.deepEqual(posted, { all: true });
  });

  // The list on the link has no ceiling, so the panel pages through it —
  // and unlike the reviewer's page this one is component state, not a
  // route, so nothing about it is exercised by visiting a URL.
  test('what is on the link is paged through in place', async function (assert) {
    const seen: (string | null)[] = [];

    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json(link({ count: 43 }));
      }),

      http.get('/sets/{set_id}/reviewer_access/accessions', ({ request, response }) => {
        const page = new URL(request.url).searchParams.get('page');

        seen.push(page);

        return response(200).json([{ ...mine, accession: page === '3' ? 'PRJDB3333' : 'PRJDB1111' }], {
          headers: { 'Total-Pages': '3' },
        });
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-shared]').includesText('PRJDB1111');

    await click('[aria-label="Next page of what is on the link"]');

    assert.dom('[data-test-shared]').includesText('PRJDB1111');

    // Both ends, not only the neighbours: these lists are as long as what
    // the members submitted.
    await click('[aria-label="Last page of what is on the link"]');

    assert.dom('[data-test-shared]').includesText('PRJDB3333');
    assert.deepEqual(seen, ['1', '2', '3']);

    await click('[aria-label="First page of what is on the link"]');

    assert.dom('[data-test-shared]').includesText('PRJDB1111');
  });

  // Reachable without anybody doing anything wrong: the rows are resolved
  // through the set on every read, so a page can empty while somebody is
  // looking at it — and the way back has to survive that.
  test('a page that has emptied still offers the way back', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json(link({ count: 43 }));
      }),

      http.get('/sets/{set_id}/reviewer_access/accessions', ({ request, response }) => {
        const page = new URL(request.url).searchParams.get('page');

        return response(200).json(page === '2' ? [] : [mine], { headers: { 'Total-Pages': '3' } });
      }),
    );

    await visit('/sets/7');
    await click('[aria-label="Next page of what is on the link"]');

    assert.dom('[data-test-shared]').doesNotExist();
    assert.dom('[data-test-reviewer-access]').includesText('Nothing on this page');
    assert.dom('[data-test-reviewer-access]').doesNotIncludeText('carries nothing yet');
    assert.dom('[aria-label="Previous page of what is on the link"]').exists('the way back is still there');
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
        return response(200).json(link({ count: 2, others: 1 }));
      }),

      http.get('/sets/{set_id}/reviewer_access/accessions', ({ response }) => {
        return response(200).json([mine, theirs]);
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

    await click('[data-test-confirm-action]');

    assert.true(revoked);
    assert.dom('[data-test-shared]').doesNotExist();
  });

  test('an expired link says so rather than offering a URL that 404s', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
        return response(200).json(link({ expired: true, count: 1 }));
      }),

      http.get('/sets/{set_id}/reviewer_access/accessions', ({ response }) => {
        return response(200).json([mine]);
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
        return response(200).json(link());
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
