import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Review = paths['/reviews/{token}']['get']['responses']['200']['content']['application/json'];

// No auth gate: a reviewer follows a share link without logging in. The
// token endpoint ignores any Authorization header.
//
// The link itself is one row — what it carries has no ceiling and arrives
// a page at a time, which is the index route's request. Split that way
// because the record page under it needs the link and not the list: its
// breadcrumb says which set the reviewer came from, and a page of
// accessions it will not draw is a page nobody asked for.
export default class ReviewRoute extends Route {
  @service declare requestManager: RequestManager;

  async model({ token }: { token: string }) {
    const { content } = await this.requestManager.request<Review>({
      url: `/reviews/${token}`,
    });

    return { token, name: content.name, expires_at: content.expires_at };
  }
}
