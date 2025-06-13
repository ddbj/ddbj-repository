import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';
import type RouterService from '@ember/routing/router-service';

export default class IndexRoute extends Route {
  @service declare currentUser: CurrentUser;
  @service declare router: RouterService;

  beforeModel() {
    if (this.currentUser.isLoggedIn) {
      this.router.transitionTo('validations.index', { queryParams: { page: undefined } });
    }
  }
}
