import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';
import type { Phase } from 'repository/controllers/index';
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
    sourceId: { refreshModel: true },
    accession: { refreshModel: true },
    phase: { refreshModel: true },
    needsAction: { refreshModel: true },
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
    sourceId,
    accession,
    phase,
    needsAction,
    page,
  }: {
    db?: string[];
    sourceId?: string;
    accession?: string;
    phase?: Phase;
    needsAction?: boolean;
    page?: number;
  }) {
    const { content, response } = await this.requestManager.request<SubmissionRequestSummaries>({
      url: '/submission_requests',
      options: {
        params: {
          db,
          source_id: sourceId || undefined,
          accession: accession || undefined,
          phase,
          needs_action: needsAction || undefined,
          page,
        },
      },
    });

    // Both halves are reported whichever one is being listed, so the tabs
    // can carry their counts without a second round trip.
    return {
      requests: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
      unfinishedCount: Number(response?.headers?.get('Unfinished-Count')) || 0,
      finishedCount: Number(response?.headers?.get('Finished-Count')) || 0,
    };
  }
}
