import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestManager from '@ember-data/request';
import type { paths } from 'schema/openapi';

type Submission = paths['/submissions/{id}']['get']['responses']['200']['content']['application/json'];

export default class SubmissionRoute extends Route {
  @service declare requestManager: RequestManager;

  async model({ submission_id }: { submission_id: string }) {
    const { content } = await this.requestManager.request<Submission>({
      url: `/submissions/${submission_id}`,
    });

    return content;
  }
}
