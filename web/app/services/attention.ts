import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import type CurrentUserService from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Attention = paths['/attention']['get']['responses']['200']['content']['application/json'];

export type AttentionRequest = Attention['requests'][number];

// What is waiting on the submitter, across every request they own.
//
// An unread-message badge on a list row is only visible if that row
// happens to be on the page in front of you — page 2 of a long list hides
// it entirely. This backs a banner rendered on every screen instead, and
// is refreshed after each navigation so replying to a curator clears it
// without a reload.
export default class AttentionService extends Service {
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;

  @tracked requests: AttentionRequest[] = [];

  // Two refreshes race on every visit to a request: one on navigation, one
  // after the thread fetch that marks its messages read. Whichever was
  // issued last is the one that saw the newest state, so an older response
  // landing late must not overwrite it.
  #generation = 0;

  get count() {
    return this.requests.length;
  }

  async refresh() {
    const generation = ++this.#generation;

    if (!this.currentUser.isLoggedIn) {
      this.requests = [];
      return;
    }

    try {
      const { content } = await this.requestManager.request<Attention>({ url: '/attention' });

      if (generation === this.#generation) this.requests = content.requests;
    } catch {
      // A banner is an aid, not the task. Losing it must never take the
      // page down with it.
      if (generation === this.#generation) this.requests = [];
    }
  }
}
