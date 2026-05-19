import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type AdminSubmissionRequests =
  paths['/admin/submission_requests']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    db: { refreshModel: true },
    user: { refreshModel: true },
    page: { refreshModel: true },
  };

  async model({ db, user, page }: { db?: string; user?: string; page?: number }) {
    const { content, response } = await this.requestManager.request<AdminSubmissionRequests>({
      url: '/admin/submission_requests',
      options: { params: { db, user, page } },
    });

    return {
      requests: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
