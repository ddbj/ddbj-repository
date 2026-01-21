import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'repository/config/environment';

import type RequestService from 'repository/services/request';
import type { paths } from 'schema/openapi';

export default class extends Route {
  @service declare request: RequestService;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const url = new URL('/api/submission_requests', ENV.apiURL);

    if (page) {
      url.searchParams.set('page', page.toString());
    }

    const res = await this.request.fetch(url.toString());

    return {
      requests:
        (await res.json()) as paths['/submission_requests']['get']['responses']['200']['content']['application/json'],
      totalPages: Number(res.headers.get('Total-Pages')) || 1,
    };
  }
}
