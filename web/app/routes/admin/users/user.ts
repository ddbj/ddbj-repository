import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type AdminUserDetail = paths['/admin/users/{uid}']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  async model({ uid }: { uid: string }) {
    const { content } = await this.requestManager.request<AdminUserDetail>({
      url: `/admin/users/${encodeURIComponent(uid)}`,
    });

    return content;
  }
}
