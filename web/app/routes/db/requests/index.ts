import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type SubmissionRequestSummary =
  paths['/{db}/submission_requests']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const { db } = this.paramsFor('db') as { db: string };

    const { content, response } = await this.requestManager.request<SubmissionRequestSummary>({
      url: `/${db}/submission_requests`,
      options: { params: { page } },
    });

    return {
      db,
      requests: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
