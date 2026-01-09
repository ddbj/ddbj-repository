import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';

export default class extends Route {
  @service declare request: RequestService;

  async model({ update_id }) {
    const res = await this.request.fetchWithModal(`/submission_updates/${update_id}`);

    return res.json();
  }
}
