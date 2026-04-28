import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type SubmissionRequest =
  paths['/{db}/submission_requests/{id}']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  async model({ request_id }: { request_id: string }) {
    const { db } = this.paramsFor('db') as { db: string };

    const { content } = await this.requestManager.request<SubmissionRequest>({
      url: `/${db}/submission_requests/${request_id}`,
    });

    return { db, ...content };
  }
}
