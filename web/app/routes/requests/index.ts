import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestManager from '@ember-data/request';
import type { paths } from 'schema/openapi';

type SubmissionRequestSummary = paths['/submission_requests']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    const { content, response } = await this.requestManager.request<SubmissionRequestSummary>({
      url: '/submission_requests',
      options: { params: { page } },
    });

    return {
      requests: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
