import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class ValidationsRoute extends Route {
  @service declare currentUser: CurrentUserService;

  timer?: number;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model(params: { page?: string }) {
    const url = new URL(`${ENV.apiURL}/validations`);

    if (params.page) {
      url.searchParams.set('page', params.page);
    }

    const res = await fetch(url, {
      headers: this.currentUser.authorizationHeader,
    });

    if (!res.ok) {
      throw new Error(res.statusText);
    }

    return {
      validations: await res.json(),
      lastPage: getLastPageFromLinkHeader(res.headers.get('Link')),
    };
  }

  afterModel(model: { validations: { progress: string }[] }) {
    if (model.validations.some(({ progress }) => progress === 'waiting' || progress === 'running')) {
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

function getLastPageFromLinkHeader(header: string | null) {
  if (!header) return undefined;

  const match = header.match(/(?<=<)(\S+)(?=>; rel="last")/);

  if (!match) return undefined;

  return parseInt(new URL(match[0]).searchParams.get('page')!, 10);
}
