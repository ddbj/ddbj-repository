import Route from '@ember/routing/route';
import { service } from '@ember/service';
import { action } from '@ember/object';

import { LoginError } from 'repository/services/current-user';

import type CurrentUserService from 'repository/services/current-user';
import type LoadingService from 'repository/services/loading';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';

export default class ApplicationRoute extends Route {
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

    const url = new URL(location.href);
    const proxyUid = url.searchParams.get('proxy_login');

    if (proxyUid && this.currentUser.isLoggedIn) {
      this.currentUser.startProxy(proxyUid);

      url.searchParams.delete('proxy_login');
      window.history.replaceState(null, '', url.toString());
    }
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
