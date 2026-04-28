import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type SubmissionUpdate =
  paths['/{db}/submission_updates/{id}']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  async model({ update_id }: { update_id: string }) {
    const { db } = this.paramsFor('db') as { db: string };

    const { content } = await this.requestManager.request<SubmissionUpdate>({
      url: `/${db}/submission_updates/${update_id}`,
    });

    return { db, ...content };
  }
}
