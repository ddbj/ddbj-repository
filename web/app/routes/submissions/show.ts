import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionsShowRoute extends Route {
  @service declare request: RequestService;

  timer?: number;

  async model({ id }: { id: string }) {
    const res = await this.request.fetch(`/submissions/${id}`);

    return (await res.json()) as Submission;
  }

  afterModel({ progress }: Submission) {
    if (progress === 'waiting' || progress === 'running') {
      this.timer = setTimeout(() => {
        this.refresh();
      }, 2000);
    }
  }

  deactivate() {
    if (this.timer) {
      clearTimeout(this.timer);
    }
  }
}
