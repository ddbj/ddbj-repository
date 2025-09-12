import Route from '@ember/routing/route';

import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionIndexRoute extends Route {
  timer?: number;

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
