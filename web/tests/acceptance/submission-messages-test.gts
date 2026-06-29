import { module, test } from 'qunit';
import { visit, fillIn, click } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Message = components['schemas']['Message'];

const now = '2025-01-01T00:00:00.000Z';

// Minimal Submission shape the show route needs to render. Cast through
// `as never` so the pre-existing `updates` field drift in the schema
// doesn't fail tsc here.
const submission = {
  id: 1,
  created_at: now,
  updated_at: now,
  ddbj_record: { filename: 'original.json', url: 'http://example.com/original.json' },
  flatfile_na: null,
  flatfile_aa: null,
  updates: [],
} as never;

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
      http.get('/submissions/{id}', ({ response }) => {
        return response(200).json(submission);
      }),

      http.get('/submissions/{submission_id}/messages', ({ response }) => {
        return response(200).json(initial);
      }),

      http.post('/submissions/{submission_id}/messages', ({ response }) => {
        return response(201).json(posted);
      }),
    );

    await visit('/st26/submissions/1');

    // Existing curator message renders with the labelled author.
    assert.dom('section h2').includesText('Messages');
    assert.dom('section li').exists({ count: 1 });
    assert.dom('section li strong').hasText('Curator');
    assert.dom('section li').includesText('Please add an organism description.');

    // Submit a reply and verify the optimistic append.
    await fillIn('section textarea', 'Updated, please review.');
    await click('section button[type="submit"]');

    assert.dom('section li').exists({ count: 2 });
    assert.dom('section li:nth-of-type(2) strong').hasText('You');
    assert.dom('section li:nth-of-type(2)').includesText('Updated, please review.');
    // Textarea is cleared after a successful post.
    assert.dom('section textarea').hasValue('');
  });
});
