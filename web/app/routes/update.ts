import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type SubmissionUpdate = paths['/submission_updates/{id}']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  async model({ update_id }: { update_id: string }) {
    const { content } = await this.requestManager.request<SubmissionUpdate>({
      url: `/submission_updates/${update_id}`,
    });

    return content;
  }
}
