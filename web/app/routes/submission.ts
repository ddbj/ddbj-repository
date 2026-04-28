import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Submission = paths['/{db}/submissions/{id}']['get']['responses']['200']['content']['application/json'];

export default class SubmissionRoute extends Route {
  @service declare requestManager: RequestManager;

  async model({ submission_id }: { submission_id: string }) {
    const { db } = this.paramsFor('db') as { db: string };

    const { content } = await this.requestManager.request<Submission>({
      url: `/${db}/submissions/${submission_id}`,
    });

    return { db, ...content };
  }
}
