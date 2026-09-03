import { module, test } from 'qunit';
import { visit, click } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type SubmissionRequest = components['schemas']['SubmissionRequest'];
type Detail = components['schemas']['Validation']['details'][number];

const now = '2025-01-01T00:00:00.000Z';

function detail(attrs: Partial<Detail> & Pick<Detail, 'code' | 'message'>): Detail {
  return { entry_id: null, severity: 'error', ...attrs };
}

function requestWith(details: Detail[]): SubmissionRequest {
  return {
    id: 42,
    db: 'biosample',
    status: 'validation_failed',
    error_code: null,
    error_message: null,
    created_at: now,
    closed_at: null,
    closable: true,
    sendable: true,
    send_blocked_reason: null,
    recheckable: false,
    processing: false,
    last_message_at: null,
    sets: [],
    owned: true,
    owner_uid: 'test-user',
    unread_curator_message_count: 0,
    ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
    validation: {
      id: 1,
      progress: 'finished',
      created_at: now,
      finished_at: now,
      validity: 'invalid',
      details,
    },
    submission: null,
    progress: {
      step: 'submitted',
      failed: true,
      closed: false,
      row_count: 0,
      accessioned_count: 0,
      hold_date: null,
    },
  };
}

module('Acceptance | validation report', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  hooks.beforeEach(function () {
    worker.use(
      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),
    );
  });

  // Two hundred findings are rarely two hundred problems. The old report
  // listed every one, which is the same information and none of the work.
  test('findings are grouped by what to change, most common first', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(
          requestWith([
            detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: 'S1' }),
            detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: 'S2' }),
            detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: 'S3' }),
            detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: 'S4' }),
            detail({ code: 'BS_R0014', message: 'Tax ID does not exist', entry_id: 'S9' }),
          ]),
        ),
      ),
    );

    await visit('/requests/42');

    const rows = document.querySelectorAll('[data-test-findings] tbody tr');

    assert.strictEqual(rows.length, 2, 'five findings, two things to change');
    assert.dom(rows[0]).includesText('collection_date must be a date');
    assert.dom(rows[0]).includesText('4');

    // Enough identifiers to recognise which records, not the list it
    // replaced.
    assert.dom(rows[0]).includesText('S1, S2, S3, …');

    // The code reaches DDBJ's description of the rule, so it is always
    // there — as a column, not as the heading.
    assert.dom('[data-test-findings] a[href*="BS_R0037"]').exists();
  });

  // The first question after a failed check is whether some of it went
  // through anyway.
  test('the report says nothing was sent before it says anything else', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(requestWith([detail({ code: 'BS_R0037', message: 'collection_date must be a date' })])),
      ),
    );

    await visit('/requests/42');

    assert.dom('[data-test-nothing-sent]').includesText('Nothing has been sent to DDBJ');
  });

  // One blocks sending and the other does not, and mixed together a
  // submitter works through all of them before daring to continue.
  test('must-fix and worth-checking are separate, and start on what blocks', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(
          requestWith([
            detail({ code: 'BS_R0037', message: 'collection_date must be a date' }),
            detail({ code: 'BS_R0999', message: 'organism is unusual for this package', severity: 'warning' }),
            detail({ code: 'BS_R0999', message: 'organism is unusual for this package', severity: 'warning' }),
          ]),
        ),
      ),
    );

    await visit('/requests/42');

    assert.dom('[data-test-tab="error"]').includesText('1');
    assert.dom('[data-test-tab="warning"]').includesText('2');
    assert.dom('[data-test-findings]').includesText('collection_date must be a date');
    assert.dom('[data-test-findings]').doesNotIncludeText('organism is unusual');

    await click('[data-test-tab="warning"]');

    assert.dom('[data-test-findings]').includesText('organism is unusual');
    assert.dom('[data-test-findings]').doesNotIncludeText('collection_date must be a date');
  });

  // The same findings listed twice on one screen makes the reader wonder
  // which is the real one — but the grouped view names three ids out of
  // ten, and whoever is correcting the file needs the other seven.
  test('the whole list stays, folded, under the grouped one', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(
          requestWith(
            [1, 2, 3, 4, 5].map((n) =>
              detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: `S${n}` }),
            ),
          ),
        ),
      ),
    );

    await visit('/requests/42');

    assert.dom('[data-test-validation-report]').exists();
    assert.dom('[data-test-every-finding] summary').hasText('Every finding (5)');
    assert.dom('[data-test-every-finding] tbody tr').exists({ count: 5 });

    // And not a second time further down the page.
    assert.dom('details').doesNotIncludeText('Validation report');
  });

  // A set mixing file-level and entry-level findings collects fewer
  // than three ids, and without this reads as though those were all of
  // them.
  test('the examples say when they are only some of the records', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(
          requestWith([
            detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: 'S1' }),
            detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: 'S2' }),
            detail({ code: 'BS_R0037', message: 'collection_date must be a date', entry_id: null }),
          ]),
        ),
      ),
    );

    await visit('/requests/42');

    // Two of the three carried an id, so two is the whole of what can be
    // named — and it does not pretend otherwise in either direction.
    assert.dom('[data-test-findings] tbody tr').includesText('S1, S2');
    assert.dom('[data-test-findings] tbody tr').doesNotIncludeText('S1, S2, …');
  });

  // Opening on an empty tab would be a report hiding its only content,
  // and the highlighted tab has to be the one whose table is showing.
  test('a report with only warnings opens on them', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(
          requestWith([
            detail({ code: 'BS_R0999', message: 'organism is unusual for this package', severity: 'warning' }),
          ]),
        ),
      ),
    );

    await visit('/requests/42');

    assert.dom('[data-test-tab="warning"]').hasAttribute('aria-pressed', 'true');
    assert.dom('[data-test-tab="error"]').hasAttribute('aria-pressed', 'false');
    assert.dom('[data-test-findings]').includesText('organism is unusual');
  });

  // A report that has to be opened before it says anything is a report
  // nobody reads twice.
  test('a passing check leaves the report folded away', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json({
          ...requestWith([]),
          status: 'ready_to_apply',
          validation: {
            id: 1,
            progress: 'finished',
            created_at: now,
            finished_at: now,
            validity: 'valid',
            details: [],
          },
        }),
      ),
    );

    await visit('/requests/42');

    assert.dom('[data-test-validation-report]').doesNotExist();
    assert.dom('[data-test-send]').hasText('Send to DDBJ');
  });

  // A check that passed goes stale, and the request stays `ready_to_apply`
  // while it does. The button used to be offered on the status alone and
  // answered 404 — the request had fallen out of a scope, not gone
  // missing — so what is shown now is why, and what to do about it.
  test('a check that has gone stale says so where the button was', async function (assert) {
    const rechecked: string[] = [];

    worker.use(
      http.post('/submission_requests/{submission_request_id}/validation', ({ params, response }) => {
        rechecked.push(String(params.submission_request_id));

        return response(204).empty();
      }),
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json({
          ...requestWith([]),
          status: 'ready_to_apply',
          sendable: false,
          send_blocked_reason: 'This check is more than 24 hours old. Check the file again before sending it.',
          recheckable: true,

          // The base stub is a failed request; this one passed and then
          // went stale, which is the whole point of the case.
          progress: { ...requestWith([]).progress, failed: false },

          validation: {
            id: 1,
            progress: 'finished',
            created_at: now,
            finished_at: now,
            validity: 'valid',
            details: [],
          },
        }),
      ),
    );

    await visit('/requests/42');

    // Disabled with the reason beside it, not hidden — hiding it leaves
    // somebody working out that a paragraph is standing where a button
    // was. The way out is offered next to it.
    assert.dom('[data-test-send]').isDisabled();
    assert.dom('[data-test-send-blocked]').includesText('more than 24 hours old');
    assert.dom('[data-test-recheck]').exists();

    // And the panel above agrees with it, rather than saying the file is
    // ready to submit over a button that is refusing.
    assert.dom('[data-test-state]').includesText('check on your file has expired');

    await click('[data-test-recheck]');

    assert.deepEqual(rechecked, ['42']);
  });
});
