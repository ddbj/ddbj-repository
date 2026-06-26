import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type SubmissionRequestSummaries =
  paths['/submission_requests']['get']['responses']['200']['content']['application/json'];

export default class IndexRoute extends Route {
  @service declare currentUser: CurrentUser;
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ page }: { page?: number }) {
    if (!this.currentUser.isLoggedIn) return null;

    const { content, response } = await this.requestManager.request<SubmissionRequestSummaries>({
      url: '/submission_requests',
      options: { params: { page } },
    });

    return {
      requests: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
