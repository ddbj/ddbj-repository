import { module, test } from 'qunit';
import { setupRenderingTest } from 'ddbj-repository/tests/helpers';
import { render } from '@ember/test-helpers';
import { hbs } from 'ember-cli-htmlbars';

module('Integration | Component | pagination', function (hooks) {
  setupRenderingTest(hooks);

  test('current=1, last=3', async function (assert) {
    await render(hbs`<Pagination @route="requests.index" @current={{1}} @last={{3}} />`);

    assert.dom('[data-test-prev]').hasClass('disabled');
    assert.dom('[data-test-prev] a').hasAttribute('href', '#');

    assert.dom('[data-test-next]').doesNotHaveClass('disabled');
    assert.dom('[data-test-next] a').hasAttribute('href', '/web/requests?page=2');

    assert.dom('[data-test-page="1"]').hasClass('active');
    assert.dom('[data-test-page="1"] a').hasAttribute('href', '/web/requests');

    assert.dom('[data-test-page="2"]').doesNotHaveClass('active');
    assert.dom('[data-test-page="2"] a').hasAttribute('href', '/web/requests?page=2');

    assert.dom('[data-test-page="3"]').doesNotHaveClass('active');
    assert.dom('[data-test-page="3"] a').hasAttribute('href', '/web/requests?page=3');
  });

  test('current=2, last=3', async function (assert) {
    await render(hbs`<Pagination @route="requests.index" @current={{2}} @last={{3}} />`);

    assert.dom('[data-test-prev]').doesNotHaveClass('disabled');
    assert.dom('[data-test-prev] a').hasAttribute('href', '/web/requests');

    assert.dom('[data-test-next]').doesNotHaveClass('disabled');
    assert.dom('[data-test-next] a').hasAttribute('href', '/web/requests?page=3');

    assert.dom('[data-test-page="1"]').doesNotHaveClass('active');
    assert.dom('[data-test-page="2"]').hasClass('active');
    assert.dom('[data-test-page="3"]').doesNotHaveClass('active');
  });

  test('current=3, last=3', async function (assert) {
    await render(hbs`<Pagination @route="requests.index" @current={{3}} @last={{3}} />`);

    assert.dom('[data-test-prev]').doesNotHaveClass('disabled');
    assert.dom('[data-test-prev] a').hasAttribute('href', '/web/requests?page=2');

    assert.dom('[data-test-next]').hasClass('disabled');
    assert.dom('[data-test-next] a').hasAttribute('href', '#');

    assert.dom('[data-test-page="1"]').doesNotHaveClass('active');
    assert.dom('[data-test-page="2"]').doesNotHaveClass('active');
    assert.dom('[data-test-page="3"]').hasClass('active');
  });
});
