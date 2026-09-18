import {
  setupApplicationTest as upstreamSetupApplicationTest,
  setupRenderingTest as upstreamSetupRenderingTest,
  setupTest as upstreamSetupTest,
  type SetupTestOptions,
} from 'ember-qunit';

import { worker } from '../msw/worker';

function setupApplicationTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupApplicationTest(hooks, options);

  hooks.afterEach(() => {
    worker.resetHandlers();
  });
}

function setupRenderingTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupRenderingTest(hooks, options);

  hooks.afterEach(() => {
    worker.resetHandlers();
  });
}

// Handlers a test added are its own. Without this they outlive it, and the
// next test is answered by a stub written for something else — which reads as
// the code under test misbehaving.
function setupTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupTest(hooks, options);

  hooks.afterEach(() => {
    worker.resetHandlers();
  });
}

export { setupApplicationTest, setupRenderingTest, setupTest };
