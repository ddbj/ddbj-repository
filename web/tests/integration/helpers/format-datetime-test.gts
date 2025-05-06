import { module, test } from 'qunit';
import { setupRenderingTest } from 'repository/tests/helpers';
import { render } from '@ember/test-helpers';

import formatDatetime from 'repository/helpers/format-datetime';

module('Integration | Helper | format-datetime', function (hooks) {
  setupRenderingTest(hooks);

  test('date instance', async function (assert) {
    const date = new Date(2024, 0, 2, 3, 4, 56);

    await render(<template>{{formatDatetime date}}</template>);

    assert.dom().hasText('2024-01-02 03:04:56');
  });

  test('string', async function (assert) {
    const date = '2024-01-02T03:04:56';

    await render(<template>{{formatDatetime date}}</template>);

    assert.dom().hasText('2024-01-02 03:04:56');
  });
});
