import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';
import getLastPageFromLinkHeader from 'ddbj-repository/utils/get-last-page-from-link-header';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class SubmissionsIndexRoute extends Route {
  @service declare currentUser: CurrentUserService;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model(params: { page?: string }) {
    const url = new URL(`${ENV.apiURL}/submissions`);

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
      submissions: await res.json(),
      lastPage: getLastPageFromLinkHeader(res.headers.get('Link')),
    };
  }
}
