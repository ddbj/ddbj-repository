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
    error_message: null,
    created_at: now,
    closed_at: null,
    closable: true,
    processing: false,
    last_message_at: null,
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
  // which is the real one.
  test('the folded reference copy stands down while the report is up', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(requestWith([detail({ code: 'BS_R0037', message: 'collection_date must be a date' })])),
      ),
    );

    await visit('/requests/42');

    assert.dom('[data-test-validation-report]').exists();
    assert.dom('details').doesNotIncludeText('Validation report');
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
});
