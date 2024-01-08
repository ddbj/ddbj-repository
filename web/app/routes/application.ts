import Route from '@ember/routing/route';
import { service } from '@ember/service';

import 'bootstrap';
import 'bootstrap/dist/css/bootstrap.css';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class ApplicationRoute extends Route {
  @service declare currentUser: CurrentUserService;

  async beforeModel() {
    await this.currentUser.restore();
  }
}
