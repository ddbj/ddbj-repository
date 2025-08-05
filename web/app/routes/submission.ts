import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionRoute extends Route {
  @service declare request: RequestService;

  async model({ submission_id }: { submission_id: string }) {
    const res = await this.request.fetch(`/submissions/${submission_id}`);

    return (await res.json()) as Submission;
  }
}
