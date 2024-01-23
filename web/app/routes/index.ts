import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type Router from '@ember/routing/router';

export default class IndexRoute extends Route {
  @service declare router: Router;

  beforeModel() {
    this.router.transitionTo('validations');
  }
}
