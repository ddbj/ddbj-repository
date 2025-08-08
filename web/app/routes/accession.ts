import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';
import type { components } from 'schema/openapi';

type Accession = components['schemas']['Accession'];

export default class AccessionRoute extends Route {
  @service declare request: RequestService;

  async model({ number }: { number: string }) {
    const res = await this.request.fetch(`/accessions/${number}`);

    return {
      submission: this.modelFor('submission'),
      accession: (await res.json()) as Accession
    };
  }
}
