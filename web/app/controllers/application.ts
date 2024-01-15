import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class ApplicationController extends Controller {
  @service declare currentUser: CurrentUserService;

  @tracked isLoading = false;

  @action
  async logout() {
    await this.currentUser.logout();
  }
}
