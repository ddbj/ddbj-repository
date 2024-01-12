import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class RequestsRoute extends Route {
  @service declare currentUser: CurrentUserService;

  async model() {
    const res = await fetch(`${ENV.apiURL}/requests`, {
      headers: this.currentUser.authorizationHeader,
    });

    return await res.json();
  }
}
