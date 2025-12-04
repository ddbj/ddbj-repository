import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';
import type RequestService from 'repository/services/request';
import type Transition from '@ember/routing/transition';

export default class SubmissionsRoute extends Route {
  @service declare currentUser: CurrentUserService;
  @service declare request: RequestService;

  beforeModel(transition: Transition) {
    this.currentUser.ensureLogin(transition);
  }
}
