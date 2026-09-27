import Route from '@ember/routing/route';
import { service } from '@ember/service';

import { isSubmittableDb } from 'repository/helpers/db-label';

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

  // Only what a request can be created for: a DRA request would be
  // refused on upload, after the person had chosen a file for it.
  afterModel({ db }: { db: string }) {
    if (!isSubmittableDb(db)) this.router.replaceWith('new');
  }
}
