import Route from '@ember/routing/route';
import { service } from '@ember/service';

import { DB_OPTIONS } from 'repository/controllers/index';

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
    // A value the server does not know is answered with 400, and this
    // parameter is bookmarkable — a URL kept from before a database was
    // renamed would cost the submitter the whole list rather than the
    // filter. The checkboxes only ever produce values from this list, so
    // dropping the rest loses nothing anybody chose.
    const knownDbs = db?.filter((value) => DB_OPTIONS.some((option) => option.value === value));

    const { content, response } = await this.requestManager.request<SubmissionRequestSummaries>({
      url: '/submission_requests',
      options: {
        params: {
          db: knownDbs?.length ? knownDbs : undefined,
          source_id: sourceId || undefined,
          accession: accession || undefined,
          phase,
          needs_action: needsAction || undefined,
          // Anything waiting on the submitter belongs at the top of the
          // whole list, not of whichever page they happened to open.
          // Asked for rather than assumed: it makes the leading sort key
          // move with the data, so rows can cross a page boundary while
          // somebody is reading. This screen takes that trade — a person
          // rereads the page they are on — and a client walking every
          // page to reconcile against it cannot.
          needs_action_first: true,
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
