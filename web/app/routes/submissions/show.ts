import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';
import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class SubmissionsShowRoute extends Route {
  @service declare currentUser: CurrentUserService;

  async model({ id }: { id: string }) {
    const res = await fetch(`${ENV.apiURL}/submissions/${id}`, {
      headers: this.currentUser.authorizationHeader,
    });

    if (!res.ok) {
      throw new Error(res.statusText);
    }

    return await res.json();
  }
}
