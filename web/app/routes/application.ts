import Route from '@ember/routing/route';
import { service } from '@ember/service';
import { action } from '@ember/object';

import { LoginError } from 'repository/services/current-user';

import type AttentionService from 'repository/services/attention';
import type CurrentUserService from 'repository/services/current-user';
import type LoadingService from 'repository/services/loading';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';

export default class ApplicationRoute extends Route {
  @service declare attention: AttentionService;
  @service declare currentUser: CurrentUserService;
  @service('loading') declare _loading: LoadingService;
  @service declare router: RouterService;

  async beforeModel() {
    try {
      await this.currentUser.restore();
    } catch (err) {
      // A token the server rejected is a token gone, and the routes that
      // need one send their own visitor to the sign-in screen
      // (`ensureLogin`) — so there is nothing to do here but let the
      // transition carry on without a session.
      if (err instanceof LoginError) return;

      // Anything else means we could not ask, not that the answer was
      // no. The service says so in a banner; the boot continues, because
      // taking the whole page away over one request that failed leaves
      // somebody with nothing to retry from.
      if (!this.currentUser.serverUnreachable) throw err;
    }
  }

  // Refresh the banner after every navigation rather than only at boot,
  // so replying to a curator clears the notice without a reload. Not
  // awaited — the banner must never delay a transition.
  activate() {
    this.router.on('routeDidChange', () => {
      void this.attention.refresh();
    });
  }

  @action
  loading(transition: Transition) {
    this._loading.start();

    transition.promise?.finally(() => {
      this._loading.stop();
    });

    return true;
  }
}
