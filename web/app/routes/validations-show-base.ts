import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export default abstract class ValidationsShowBaseRoute extends Route {
  @service declare request: RequestService;

  timer?: number;

  async model({ id }: { id: string }) {
    const res = await this.request.fetch(`/validations/${id}`);

    return (await res.json()) as Validation;
  }

  afterModel({ progress }: Validation) {
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
