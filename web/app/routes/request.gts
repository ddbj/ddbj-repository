import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestManager from '@ember-data/request';
import type { paths } from 'schema/openapi';

type SubmissionRequest = paths['/submission_requests/{id}']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  async model({ request_id }: { request_id: string }) {
    const { content } = await this.requestManager.request<SubmissionRequest>({
      url: `/submission_requests/${request_id}`,
    });

    return content;
  }
}
