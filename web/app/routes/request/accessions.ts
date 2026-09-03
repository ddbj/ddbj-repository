import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Accessions = paths['/submissions/{id}/accessions']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const request = this.modelFor('request') as { db: string; id: number; submission: { id: number } | null };
    const submissionId = request.submission?.id;

    const { content, response } = await this.requestManager.request<Accessions>({
      url: `/submissions/${submissionId}/accessions`,
      options: { params: { page } },
    });

    return {
      requestId: request.id,
      accessions: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
