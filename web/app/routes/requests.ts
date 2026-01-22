import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';
import type Transition from '@ember/routing/transition';

export default class SubmissionsRoute extends Route {
  @service declare currentUser: CurrentUserService;

  beforeModel(transition: Transition) {
    this.currentUser.ensureLogin(transition);
  }
}
