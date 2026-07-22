import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';

export default class LoginRoute extends Route {
  @service declare currentUser: CurrentUserService;

  async beforeModel() {
    const params = new URL(location.href).searchParams;
    const token = params.get('token')!;
    const proxyUid = params.get('proxy_login') ?? undefined;

    await this.currentUser.login(token, proxyUid);
  }
}
