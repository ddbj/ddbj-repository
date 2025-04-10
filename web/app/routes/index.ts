import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';
import type Router from '@ember/routing/router';

export default class IndexRoute extends Route {
  @service declare currentUser: CurrentUser;
  @service declare router: Router;

  beforeModel() {
    if (this.currentUser.isLoggedIn) {
      this.router.transitionTo('validations.index', { queryParams: { page: undefined } });
    }
  }
}
