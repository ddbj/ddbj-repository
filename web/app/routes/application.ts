import Route from '@ember/routing/route';
import { service } from '@ember/service';
import { action } from '@ember/object';

import { LoginError } from 'repository/services/current-user';

import type CurrentUserService from 'repository/services/current-user';
import type LoadingService from 'repository/services/loading';
import type Router from '@ember/routing/router';
import type Transition from '@ember/routing/transition';

export default class ApplicationRoute extends Route {
  @service declare currentUser: CurrentUserService;
  @service('loading') declare _loading: LoadingService;
  @service declare router: Router;

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

  @action
  loading(transition: Transition) {
    this._loading.start();

    transition.promise?.finally(() => {
      this._loading.stop();
    });

    return true;
  }
}
