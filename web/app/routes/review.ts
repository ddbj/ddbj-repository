import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Review = paths['/reviews/{token}']['get']['responses']['200']['content']['application/json'];

// No auth gate: a reviewer follows a share link without logging in. The
// token endpoint ignores any Authorization header.
export default class ReviewRoute extends Route {
  @service declare requestManager: RequestManager;

  async model({ token }: { token: string }) {
    const { content } = await this.requestManager.request<Review>({
      url: `/reviews/${token}`,
    });

    return content;
  }
}
