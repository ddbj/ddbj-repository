import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import type CurrentUserService from 'repository/services/current-user';

export default class AdminProxyLoginController extends Controller {
  @service declare currentUser: CurrentUserService;

  @tracked uid?: string;

  @action
  setUid(e: Event) {
    this.uid = (e.target as HTMLInputElement).value;
  }

  @action
  submit(e: Event) {
    e.preventDefault();

    this.currentUser.proxyUid = this.uid;
  }

  @action
  exit() {
    this.currentUser.proxyUid = this.uid = undefined;
  }
}
