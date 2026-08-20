import { module, test } from 'qunit';
import { visit, click, settled } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Summary = components['schemas']['SubmissionRequestSummary'];
type SetSummary = components['schemas']['SetSummary'];

const now = '2025-01-01T00:00:00.000Z';

function summary(id: number): Summary {
  return {
    id,
    db: 'st26',
    status: 'applied',
    created_at: now,
    closed_at: null,
    submission_id: null,
    source_id: null,
    first_accession: null,
    accession_count: 0,
    processing: false,
    unread_curator_message_count: 0,
    progress: {
      step: 'applied',
      failed: false,
      closed: false,
      row_count: 0,
      accessioned_count: 0,
      hold_date: null,
    },
  };
}

const mine: SetSummary = {
  id: 7,
  name: 'Deep sea study',
  owner_uid: 'test-user',
  owned: true,
  created_at: now,
  member_count: 1,
  invited_count: 0,
  submission_count: 0,
};

const rows = [summary(1), summary(2), summary(3)];

const listHeaders = {
  headers: { 'Total-Pages': '1', 'Unfinished-Count': '3', 'Finished-Count': '0' },
};

function stubList(sets: SetSummary[] = [mine]) {
  worker.use(
    http.get('/submission_requests', ({ response }) => {
      return response(200).json(rows, listHeaders);
    }),

    http.get('/sets', ({ response }) => {
      return response(200).json(sets);
    }),
  );
}

module('Acceptance | adding several submissions to a set at once', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('nothing is offered until something is ticked', async function (assert) {
    stubList();

    await visit('/');

    assert.dom('[data-test-bulk-add]').doesNotExist();

    await click('[aria-label="Select submission #1"]');

    assert.dom('[data-test-bulk-add]').includesText('1 selected on this page');
  });

  test('the whole page can be ticked at once', async function (assert) {
    stubList();

    await visit('/');
    await click('[data-test-select-all]');

    assert.dom('[data-test-bulk-add]').includesText('3 selected on this page');

    await click('[data-test-select-all]');

    assert.dom('[data-test-bulk-add]').doesNotExist();
  });

  // Both numbers: "2 added" alone leaves somebody who ticked three
  // wondering about the other one.
  test('adding reports what went in and what was already there', async function (assert) {
    let posted: number[] = [];

    stubList();

    worker.use(
      http.post('/sets/{set_id}/submissions', async ({ request, response }) => {
        posted = (await request.json()).submission_request_ids;

        return response(200).json({ added: 2, already_in_set: 1 });
      }),
    );

    await visit('/');
    await click('[data-test-select-all]');
    await fillInSelect('[data-test-bulk-add] select', '7');
    await click('[data-test-bulk-add] button.btn-primary');

    assert.deepEqual(posted, [1, 2, 3], 'sends the ticked ids as one list');
    assert.dom('.toast').includesText('2 submissions added to the set');
    assert.dom('.toast').includesText('1 was already in it');

    // The selection is spent — leaving it ticked invites a second press
    // that would do nothing and say so.
    assert.dom('[data-test-bulk-add]').doesNotExist();
  });

  test('with no sets at all it says how to get one instead of offering an empty picker', async function (assert) {
    stubList([]);

    await visit('/');
    await click('[aria-label="Select submission #1"]');

    assert.dom('[data-test-bulk-add] select').doesNotExist();
    assert.dom('[data-test-bulk-add]').includesText('Create a set');
  });

  test('a refusal lands on the bar rather than in a modal over the list', async function (assert) {
    stubList();

    worker.use(
      http.post('/sets/{set_id}/submissions', ({ response }) => {
        return response(422).json({ error: 'Too many at once — 200 is the maximum.' });
      }),
    );

    await visit('/');
    await click('[data-test-select-all]');
    await fillInSelect('[data-test-bulk-add] select', '7');
    await click('[data-test-bulk-add] button.btn-primary');

    assert.dom('[data-test-bulk-add] [data-test-error]').includesText('Too many at once');
    assert.dom('.modal.show').doesNotExist();
  });

  // Ticking is scoped to the rows on screen, and "on screen" changes
  // when the list is re-fetched. Without this, paging away and back
  // brings the old ticks with it — the forgotten selection the scope
  // exists to prevent.
  test('changing the list drops what was ticked against the old rows', async function (assert) {
    stubList();

    await visit('/');
    await click('[aria-label="Select submission #1"]');

    assert.dom('[data-test-bulk-add]').includesText('1 selected on this page');

    await click('[data-test-phase="finished"]');

    assert.dom('[data-test-bulk-add]').doesNotExist();

    await click('[data-test-phase="unfinished"]');

    assert.dom('[data-test-bulk-add]').doesNotExist();
  });

  // A set list that could not be read must not leave an empty bordered
  // box above the table.
  test('a failed set list shows nothing rather than an empty card', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json(rows, listHeaders);
      }),

      // Raw, not typed: the contract does not declare a 500 on this
      // endpoint, and the point here is what the screen does when one
      // arrives anyway.
      mswHttp.get(`${ENV.apiURL}/sets`, () => {
        return HttpResponse.json({ error: 'Internal server error' }, { status: 500 });
      }),
    );

    await visit('/');
    await click('[aria-label="Select submission #1"]');

    assert.dom('[data-test-bulk-add]').doesNotExist();
  });
});

// `fillIn` on a <select> dispatches `input`; this component listens for
// `change`, which is what a person picking an option actually produces.
async function fillInSelect(selector: string, value: string) {
  const el = document.querySelector(selector) as HTMLSelectElement;

  el.value = value;
  el.dispatchEvent(new Event('change', { bubbles: true }));

  await settled();
}
