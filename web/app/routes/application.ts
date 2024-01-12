import Route from '@ember/routing/route';
import { service } from '@ember/service';

import 'bootstrap';
import 'bootstrap/dist/css/bootstrap.css';

import { LoginError } from 'ddbj-repository/services/current-user';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type Router from '@ember/routing/router';

export default class ApplicationRoute extends Route {
  @service declare currentUser: CurrentUserService;
  @service declare router: Router;

  async beforeModel() {
    try {
      await this.currentUser.restore();
    } catch (err) {
      if (!(err instanceof LoginError)) throw err;

      this.router.transitionTo('login');
    }
  }
}
