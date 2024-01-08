import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class IndexController extends Controller {
  @service declare currentUser: CurrentUserService;

  @action
  async logout() {
    await this.currentUser.logout();
  }
}
