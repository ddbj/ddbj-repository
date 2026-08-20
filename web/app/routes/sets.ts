import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type Transition from '@ember/routing/transition';
import type { paths } from 'schema/openapi';

type Sets = paths['/sets']['get']['responses']['200']['content']['application/json'];

export default class SetsRoute extends Route {
  @service declare currentUser: CurrentUser;
  @service declare requestManager: RequestManager;

  beforeModel(transition: Transition) {
    this.currentUser.ensureLogin(transition);
  }

  async model() {
    const { content } = await this.requestManager.request<Sets>({ url: '/sets' });

    return content;
  }
}
