import Route from '@ember/routing/route';
import { service } from '@ember/service';
import { action } from '@ember/object';

import 'bootstrap';
import 'bootstrap/dist/css/bootstrap.css';

import { LoginError } from 'ddbj-repository/services/current-user';

import type ApplicationController from 'ddbj-repository/controllers/application';
import type CurrentUserService from 'ddbj-repository/services/current-user';
import type Router from '@ember/routing/router';
import type Transition from '@ember/routing/transition';

export default class ApplicationRoute extends Route {
  @service declare currentUser: CurrentUserService;
  @service declare router: Router;

  async beforeModel() {
    try {
      await this.currentUser.restore();
    } catch (err) {
      if (err instanceof LoginError) {
        this.router.transitionTo('login');
      } else {
        throw err;
      }
    }
  }

  @action
  loading(transition: Transition) {
    // eslint-disable-next-line ember/no-controller-access-in-routes
    const controller = this.controllerFor('application') as ApplicationController;

    controller.isLoading = true;

    transition.promise.finally(() => {
      controller.isLoading = false;
    });
  }
}
