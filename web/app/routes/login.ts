import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class LoginRoute extends Route {
  @service declare currentUser: CurrentUserService;

  beforeModel() {
    this.currentUser.ensureLogout();
  }

  async model() {
    const res = await fetch(`${ENV.apiURL}/api-key`);

    return await res.json();
  }
}
