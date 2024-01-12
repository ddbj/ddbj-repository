import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class RequestsShowRoute extends Route {
  @service declare currentUser: CurrentUserService;

  timer?: number;

  async model({ id }: { id: string }) {
    const res = await fetch(`${ENV.apiURL}/requests/${id}`, {
      headers: this.currentUser.authorizationHeader,
    });

    return await res.json();
  }

  afterModel({ status }: { status: string }) {
    if (status !== 'finished' && status !== 'canceled') {
      this.timer = setTimeout(() => {
        this.refresh();
      }, 1000);
    }
  }

  deactivate() {
    if (this.timer) {
      clearTimeout(this.timer);
    }
  }
}
