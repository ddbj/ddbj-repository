import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';
import type { components } from 'schema/openapi';

type Accession = components['schemas']['Accession'];
type Renewal = components['schemas']['AccessionRenewal'];

export default class AccessionRenewalRoute extends Route {
  @service declare request: RequestService;

  timer?: number;

  async model({ accession_renewal_id }: { accession_renewal_id: string }) {
    const res = await this.request.fetch(`/accession_renewals/${accession_renewal_id}`);
    const renewal = (await res.json()) as Renewal;
    const { accession } = this.modelFor('accession') as { accession: Accession };

    return { accession, renewal };
  }

  afterModel({ renewal: { progress } }: { renewal: Renewal }) {
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
