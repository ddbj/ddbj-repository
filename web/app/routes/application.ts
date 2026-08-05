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
      if (err instanceof LoginError) {
        this.router.transitionTo('index');
      } else {
        throw err;
      }
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
