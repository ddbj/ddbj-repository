import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type RequestManager from '@ember-data/request';

interface Status {
  loading: boolean;
  total: number | null;
  processed: number | null;
}

export interface Model {
  status: Status;
}

export default class AdminRegenerateFlatfilesRoute extends Route {
  @service declare requestManager: RequestManager;

  async model(): Promise<Model> {
    const { content } = await this.requestManager.request<Status>({
      url: '/admin/regenerate_flatfiles',
    });

    return { status: content };
  }
}
