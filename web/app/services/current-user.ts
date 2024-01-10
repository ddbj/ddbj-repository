import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import ENV from 'ddbj-repository/config/environment';

import type Router from '@ember/routing/router';

export default class CurrentUserService extends Service {
  @service declare router: Router;

  @tracked apiKey?: string;
  @tracked uid?: string;

  get isLoggedIn() {
    return !!this.apiKey;
  }

  ensureLogin() {
    if (!this.isLoggedIn) {
      this.router.transitionTo('login');
    }
  }

  ensureLogout() {
    if (this.isLoggedIn) {
      this.router.transitionTo('index');
    }
  }

  async login(apiKey: string) {
    localStorage.setItem('apiKey', apiKey);

    await this.restore();

    this.router.transitionTo('index');
  }

  async logout() {
    localStorage.removeItem('apiKey');

    await this.restore();

    this.router.transitionTo('index');
  }

  async restore() {
    this.apiKey = localStorage.getItem('apiKey') || undefined;

    if (this.apiKey) {
      const res = await fetch(`${ENV.apiURL}/me`, {
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
        },
      });

      const { uid } = await res.json();

      this.uid = uid;
    } else {
      this.uid = undefined;
    }
  }
}
