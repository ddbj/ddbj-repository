import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Review = paths['/reviews/{token}']['get']['responses']['200']['content']['application/json'];
type Accessions = paths['/reviews/{token}/accessions']['get']['responses']['200']['content']['application/json'];

// No auth gate: a reviewer follows a share link without logging in. The
// token endpoint ignores any Authorization header.
//
// Two requests, because what the link carries has no ceiling and arrives a
// page at a time — the link itself is one row and the list is however long
// the members made it.
export default class ReviewRoute extends Route {
  @service declare requestManager: RequestManager;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model({ token, page }: { token: string; page?: number }) {
    const { content: review } = await this.requestManager.request<Review>({
      url: `/reviews/${token}`,
    });

    const { content: accessions, response } = await this.requestManager.request<Accessions>({
      url: `/reviews/${token}/accessions`,
      options: { params: { page } },
    });

    return {
      token,
      name: review.name,
      expires_at: review.expires_at,
      accessions,
      page: Number(page) || 1,
      totalPages: Number(response?.headers?.get('Total-Pages')) || 1,
    };
  }
}
