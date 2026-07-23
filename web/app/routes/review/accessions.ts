import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Accessions = paths['/reviews/{token}/accessions']['get']['responses']['200']['content']['application/json'];

// Token-scoped, unauthenticated accessions list for a reviewer.
export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const { token } = this.paramsFor('review') as { token: string };

    const { content, response } = await this.requestManager.request<Accessions>({
      url: `/reviews/${token}/accessions`,
      options: { params: { page } },
    });

    return {
      token,
      accessions: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
