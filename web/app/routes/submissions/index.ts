import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'repository/config/environment';

import type RequestService from 'repository/services/request';

export default class extends Route {
  @service declare request: RequestService;

  async model() {
    const res = await this.request.fetch(`${ENV.apiURL}/submissions`);

    return await res.json();
  }
}
