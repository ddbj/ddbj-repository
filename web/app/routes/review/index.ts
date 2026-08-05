import Route from '@ember/routing/route';

import type ReviewRoute from 'repository/routes/review';

export default class extends Route {
  model() {
    return this.modelFor('review') as Awaited<ReturnType<ReviewRoute['model']>>;
  }
}
