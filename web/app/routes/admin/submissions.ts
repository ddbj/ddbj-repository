import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type AdminSubmissions = paths['/admin/submissions']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    db: { refreshModel: true },
    user: { refreshModel: true },
    page: { refreshModel: true },
  };

  async model({ db, user, page }: { db?: string; user?: string; page?: number }) {
    const { content, response } = await this.requestManager.request<AdminSubmissions>({
      url: '/admin/submissions',
      options: { params: { db, user, page } },
    });

    return {
      submissions: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
