import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class ValidationsShowRoute extends Route {
  @service declare currentUser: CurrentUserService;

  timer?: number;

  async model({ id }: { id: string }) {
    const res = await fetch(`${ENV.apiURL}/validations/${id}`, {
      headers: this.currentUser.authorizationHeader,
    });

    if (!res.ok) {
      throw new Error(res.statusText);
    }

    return await res.json();
  }

  afterModel({ progress }: { progress: string }) {
    if (progress === 'waiting' || progress === 'running') {
      this.timer = setTimeout(() => {
        this.refresh();
      }, 2000);
    }
  }

  deactivate() {
    if (this.timer) {
      clearTimeout(this.timer);
    }
  }
}
