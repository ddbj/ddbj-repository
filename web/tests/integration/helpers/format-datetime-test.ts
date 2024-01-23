import { module, test } from 'qunit';
import { setupRenderingTest } from 'ddbj-repository/tests/helpers';
import { render } from '@ember/test-helpers';
import { hbs } from 'ember-cli-htmlbars';

import type { TestContext } from '@ember/test-helpers';

interface Context extends TestContext {
  date?: Date;
}

module('Integration | Helper | format-datetime', function (hooks) {
  setupRenderingTest(hooks);

  test('date instance', async function (this: Context, assert) {
    this.set('date', new Date(2024, 0, 2, 3, 4, 56));

    await render<Context>(hbs`{{format-datetime this.date}}`);

    assert.dom().hasText('2024-01-02 03:04:56');
  });

  test('string', async function (this: Context, assert) {
    this.set('date', new Date(2024, 0, 2, 3, 4, 56).toISOString());

    await render<Context>(hbs`{{format-datetime this.date}}`);

    assert.dom().hasText('2024-01-02 03:04:56');
  });

  test('undefined', async function (assert) {
    await render(hbs`{{format-datetime undefined}}`);

    assert.dom().hasNoText();
  });
});
