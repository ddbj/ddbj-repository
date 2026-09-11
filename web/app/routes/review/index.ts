import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type ReviewRoute from 'repository/routes/review';
import type { paths } from 'schema/openapi';

type Accessions = paths['/reviews/{token}/accessions']['get']['responses']['200']['content']['application/json'];

// What the link carries, a page at a time.
export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const link = this.modelFor('review') as Awaited<ReturnType<ReviewRoute['model']>>;

    const { content, response } = await this.requestManager.request<Accessions>({
      url: `/reviews/${link.token}/accessions`,
      options: { params: { page } },
    });

    return {
      ...link,
      accessions: content,
      page: Number(page) || 1,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
