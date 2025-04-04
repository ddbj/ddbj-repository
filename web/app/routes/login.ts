import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';
import type RequestService from 'repository/services/request';

export default class LoginRoute extends Route {
  @service declare currentUser: CurrentUserService;
  @service declare request: RequestService;

  beforeModel() {
    this.currentUser.ensureLogout();
  }

  async model() {
    const res = await this.request.fetch('/api_key');

    return (await res.json()) as { login_url: string };
  }
}
