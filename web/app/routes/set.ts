import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type Transition from '@ember/routing/transition';
import type { paths } from 'schema/openapi';

type Set = paths['/sets/{id}']['get']['responses']['200']['content']['application/json'];

export default class SetRoute extends Route {
  @service declare currentUser: CurrentUser;
  @service declare requestManager: RequestManager;

  queryParams = {
    page: { refreshModel: true },
  };

  beforeModel(transition: Transition) {
    this.currentUser.ensureLogin(transition);
  }

  // The roster comes whole; the submissions are a page of however many
  // there are. A study that ran for three years is hundreds of them.
  async model({ set_id: id, page }: { set_id: string; page?: number }) {
    const { content, response } = await this.requestManager.request<Set>({
      url: `/sets/${id}`,
      options: { params: { page } },
    });

    return {
      set: content,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
