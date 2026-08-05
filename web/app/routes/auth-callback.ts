import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';

// Not a page: the OAuth callback hands a freshly minted token over in a
// query param, which this exchanges for a session and then gets out of
// the way.
export default class AuthCallbackRoute extends Route {
  @service declare currentUser: CurrentUserService;

  async beforeModel() {
    const params = new URL(location.href).searchParams;
    const token = params.get('token')!;
    const proxyUid = params.get('proxy_login') ?? undefined;

    await this.currentUser.login(token, proxyUid);
  }
}
