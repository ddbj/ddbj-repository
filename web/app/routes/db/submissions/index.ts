import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type SubmissionSummary = paths['/{db}/submissions']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const { db } = this.paramsFor('db') as { db: string };

    const { content, response } = await this.requestManager.request<SubmissionSummary>({
      url: `/${db}/submissions`,
      options: { params: { page } },
    });

    return {
      db,
      submissions: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
