import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class RequestsRoute extends Route {
  @service declare currentUser: CurrentUserService;

  beforeModel() {
    this.currentUser.ensureLogin();
  }
}
