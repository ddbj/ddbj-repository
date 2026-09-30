import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';

export default class DbRoute extends Route {
  @service declare currentUser: CurrentUserService;
  @service declare router: RouterService;

  beforeModel(transition: Transition) {
    this.currentUser.ensureLogin(transition);
  }

  model({ db }: { db: string }) {
    return { db };
  }

  // Only what a request can be created for (User#submittableDbs): anything
  // else would be refused on upload, after the person had chosen a file for
  // it.
  afterModel({ db }: { db: string }) {
    if (!this.currentUser.user?.canSubmitTo(db)) this.router.replaceWith('new');
  }
}
