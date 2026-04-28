import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Accessions = paths['/{db}/submissions/{id}/accessions']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const { submission_id } = this.paramsFor('submission') as { submission_id: string };

    const { content, response } = await this.requestManager.request<Accessions>({
      url: `/st26/submissions/${submission_id}/accessions`,
      options: { params: { page } },
    });

    return {
      accessions: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
