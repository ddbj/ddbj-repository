import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class RequestsRoute extends Route {
  @service declare currentUser: CurrentUserService;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model(params: { page?: string }) {
    const url = new URL(`${ENV.apiURL}/requests`);

    if (params.page) {
      url.searchParams.set('page', params.page);
    }

    const res = await fetch(url, {
      headers: this.currentUser.authorizationHeader,
    });

    return {
      requests: await res.json(),
      lastPage: getLastPageFromLinkHeader(res.headers.get('Link')),
    };
  }
}

function getLastPageFromLinkHeader(header: string | null) {
  if (!header) return undefined;

  const match = header.match(/(?<=<)(\S+)(?=>; rel="last")/);

  if (!match) return undefined;

  return parseInt(new URL(match[0]).searchParams.get('page')!, 10);
}
