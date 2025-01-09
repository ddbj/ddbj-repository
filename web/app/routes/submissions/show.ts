import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';
import safeFetch from 'ddbj-repository/utils/safe-fetch';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionsShowRoute extends Route {
  @service declare currentUser: CurrentUserService;

  timer?: number;

  async model({ id }: { id: string }) {
    const res = await safeFetch(`${ENV.apiURL}/submissions/${id}`, {
      headers: this.currentUser.authorizationHeader,
    });

    return (await res.json()) as Submission;
  }

  afterModel({ progress }: Submission) {
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
