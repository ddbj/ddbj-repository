import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'repository/config/environment';
import safeFetch from 'repository/utils/safe-fetch';

import type CurrentUserService from 'repository/services/current-user';

export default class LoginRoute extends Route {
  @service declare currentUser: CurrentUserService;

  beforeModel() {
    this.currentUser.ensureLogout();
  }

  async model() {
    const res = await safeFetch(`${ENV.apiURL}/api_key`);

    return (await res.json()) as { login_url: string };
  }
}
