import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type Transition from '@ember/routing/transition';
import type { paths } from 'schema/openapi';

type SubmissionRequestSummaries =
  paths['/submission_requests']['get']['responses']['200']['content']['application/json'];

export default class IndexRoute extends Route {
  @service declare currentUser: CurrentUser;
  @service declare requestManager: RequestManager;

  queryParams = {
    db: { refreshModel: true },
    status: { refreshModel: true },
    sourceId: { refreshModel: true },
    accession: { refreshModel: true },
    page: { refreshModel: true },
  };

  // The unauthenticated case is its own screen now, so this route can
  // assume a session instead of returning null and letting the
  // template branch.
  beforeModel(transition: Transition) {
    this.currentUser.ensureLogin(transition);
  }

  async model({
    db,
    status,
    sourceId,
    accession,
    page,
  }: {
    db?: string[];
    status?: string[];
    sourceId?: string;
    accession?: string;
    page?: number;
  }) {
    const { content, response } = await this.requestManager.request<SubmissionRequestSummaries>({
      url: '/submission_requests',
      options: {
        params: {
          db,
          status,
          source_id: sourceId || undefined,
          accession: accession || undefined,
          page,
        },
      },
    });

    return {
      requests: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
