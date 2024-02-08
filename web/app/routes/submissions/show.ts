import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';
import safeFetch from 'ddbj-repository/utils/safe-fetch';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class SubmissionsShowRoute extends Route {
  @service declare currentUser: CurrentUserService;

  async model({ id }: { id: string }) {
    const res = await safeFetch(`${ENV.apiURL}/submissions/${id}`, {
      headers: this.currentUser.authorizationHeader,
    });

    return await res.json();
  }
}
