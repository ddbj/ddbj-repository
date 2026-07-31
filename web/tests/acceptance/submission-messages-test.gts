import { module, test } from 'qunit';
import { visit, fillIn, click } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Message = components['schemas']['Message'];

const now = '2025-01-01T00:00:00.000Z';

// Minimal request shape the show route needs to render. The thread now
// hangs off the request, so the submission may or may not be present.
const request: components['schemas']['SubmissionRequest'] = {
  id: 1,
  db: 'st26',
  status: 'applied',
  error_message: null,
  created_at: now,
  closed_at: null,
  closable: false,
  processing: false,
  ddbj_record: { filename: 'original.json', url: 'http://example.com/original.json' },
  validation: null,

  progress: {
    step: 'curating',
    failed: false,
    closed: false,
    row_count: 1,
    accessioned_count: 0,
    hold_date: null,
  },
  unread_curator_message_count: 0,
  last_message_at: '2025-01-02T09:30:00.000Z',
  submission: {
    id: 10,
    source_id: null,
    created_at: now,
    updated_at: now,
    ddbj_record: { filename: 'original.json', url: 'http://example.com/original.json' },
    flatfile_na: null,
    flatfile_aa: null,
    accessions_count: 0,
  },
};

module('Acceptance | submission messages', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('renders the thread and posts a reply', async function (assert) {
    const initial: Message[] = [
      {
        id: 1,
        body: 'Please add an organism description.',
        author_role: 'curator',
        author_uid: 'alice',
        created_at: now,
        read_at: null,
      },
    ];

    const posted: Message = {
      id: 2,
      body: 'Updated, please review.',
      author_role: 'submitter',
      author_uid: 'bob',
      created_at: now,
      read_at: null,
    };

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(request);
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json(initial);
      }),

      http.post('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(201).json(posted);
      }),
    );

    await visit('/requests/1');

    // The status card dates the conversation without promising a reply time.
    assert.dom('[data-test-state]').includesText('last message 2025-01-02');
    assert.dom('[data-test-state]').doesNotIncludeText('business days');

    // Existing curator message renders with the labelled author.
    assert.dom('[data-test-messages] h2').includesText('Messages with the curator');
    assert.dom('[data-test-messages] li').exists({ count: 1 });
    assert.dom('[data-test-messages] li strong').hasText('DDBJ curator');
    assert.dom('[data-test-messages] li').includesText('Please add an organism description.');

    // Submit a reply and verify the optimistic append.
    await fillIn('section textarea', 'Updated, please review.');
    await click('section button[type="submit"]');

    assert.dom('[data-test-messages] li').exists({ count: 2 });
    assert.dom('[data-test-messages] li:nth-of-type(2) strong').hasText('You');
    assert.dom('[data-test-messages] li:nth-of-type(2)').includesText('Updated, please review.');
    // Textarea is cleared after a successful post.
    assert.dom('section textarea').hasValue('');
  });
});
