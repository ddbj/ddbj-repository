import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RouterService from '@ember/routing/router-service';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionIndexRoute extends Route {
  @service declare router: RouterService;

  timer?: number;

  afterModel({ progress }: Submission) {
    if (progress === 'waiting' || progress === 'running') {
      this.timer = setTimeout(() => {
        this.router.refresh();
      }, 2000);
    }
  }

  deactivate() {
    if (this.timer) {
      clearTimeout(this.timer);
    }
  }
}
