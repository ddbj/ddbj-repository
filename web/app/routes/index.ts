import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type CurrentUser from 'repository/services/current-user';

export default class IndexRoute extends Route {
  @service declare currentUser: CurrentUser;
}
