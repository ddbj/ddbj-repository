import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';

export default class extends Route {
  @service declare request: RequestService;

  async model({ request_id }) {
    const res = await this.request.fetchWithModal(`/submission_requests/${request_id}`);

    return res.json();
  }
}
