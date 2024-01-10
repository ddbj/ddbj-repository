import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class LoginController extends Controller {
  @service declare currentUser: CurrentUserService;

  loginURL = new URL('/auth/login', ENV.apiURL).href;

  @action
  async login(e: Event) {
    e.preventDefault();

    const formData = new FormData(e.target as HTMLFormElement);

    await this.currentUser.login(formData.get('apiKey') as string);
  }
}
