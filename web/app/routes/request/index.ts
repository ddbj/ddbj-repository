import Route from '@ember/routing/route';

import type SubmissionRequestRoute from 'repository/routes/request';

export default class extends Route {
  model() {
    return this.modelFor('request') as Awaited<ReturnType<SubmissionRequestRoute['model']>>;
  }
}
