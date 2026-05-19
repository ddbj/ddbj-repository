import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type AdminUsers = paths['/admin/users']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    query: { refreshModel: true, replace: true },
    include_inactive: { refreshModel: true, replace: true },
  };

  async model({ query, include_inactive }: { query?: string; include_inactive?: string }) {
    const { content } = await this.requestManager.request<AdminUsers>({
      url: '/admin/users',
      options: { params: { query, include_inactive } },
    });

    return {
      users: content,
    };
  }
}
