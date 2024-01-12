import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import ENV from 'ddbj-repository/config/environment';

import type Router from '@ember/routing/router';

export class LoginError extends Error {}

export default class CurrentUserService extends Service {
  @service declare router: Router;

  @tracked apiKey?: string;
  @tracked uid?: string;

  get isLoggedIn() {
    return !!this.apiKey;
  }

  get authorizationHeader() {
    return { Authorization: `Bearer ${this.apiKey}` };
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

    this.apiKey = apiKey;
    this.uid = undefined;

    await this.restore();

    this.router.transitionTo('index');
  }

  async logout() {
    localStorage.removeItem('apiKey');

    this.apiKey = this.uid = undefined;

    await this.restore();

    this.router.transitionTo('index');
  }

  async restore() {
    if (!this.apiKey) {
      this.apiKey = localStorage.getItem('apiKey') || undefined;
    }

    if (this.apiKey) {
      if (!this.uid) {
        const res = await fetch(`${ENV.apiURL}/me`, {
          headers: this.authorizationHeader,
        });

        if (!res.ok) {
          localStorage.removeItem('apiKey');

          this.apiKey = this.uid = undefined;

          throw new LoginError();
        }

        const { uid } = await res.json();

        this.uid = uid;
      }
    } else {
      this.uid = undefined;
    }
  }
}
