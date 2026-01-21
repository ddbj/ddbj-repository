import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';
import type { paths } from 'schema/openapi';

export default class extends Route {
  @service declare request: RequestService;

  async model({ request_id }: { request_id: string }) {
    const res = await this.request.fetchWithModal(`/submission_requests/${request_id}`);

    return (await res.json()) as paths['/submission_requests/{id}']['get']['responses']['200']['content']['application/json'];
  }
}
