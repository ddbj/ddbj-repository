import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import ENV from 'repository/config/environment';

import type Router from '@ember/routing/router';
import type Transition from '@ember/routing/transition';

export class LoginError extends Error {}

export default class CurrentUserService extends Service {
  @service declare router: Router;

  @tracked apiKey?: string;
  @tracked isAdmin?: boolean;
  @tracked proxyUid?: string;
  @tracked uid?: string;

  previousTransition?: Transition;

  get isLoggedIn() {
    return Boolean(this.apiKey);
  }

  get isProxyLoggedIn() {
    return Boolean(this.proxyUid);
  }

  get authorizationHeader() {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.apiKey}`,
    };

    if (this.proxyUid) {
      headers['X-Dway-User-Id'] = this.proxyUid;
    }

    return headers;
  }

  ensureLogin(transition: Transition, requireAdmin = false) {
    if (requireAdmin) {
      if (this.isLoggedIn && this.isAdmin) return;
    } else {
      if (this.isLoggedIn) return;
    }

    this.previousTransition = transition;

    this.router.transitionTo('login');
  }

  ensureLogout() {
    if (!this.isLoggedIn) return;

    this.router.transitionTo('index');
  }

  async login(apiKey: string) {
    this.clear();
    localStorage.setItem('apiKey', apiKey);

    await this.restore();

    if (this.previousTransition) {
      this.previousTransition.retry();
      this.previousTransition = undefined;
    } else {
      this.router.transitionTo('index');
    }
  }

  logout() {
    this.clear();
    localStorage.removeItem('apiKey');

    this.router.transitionTo('index');
  }

  async restore() {
    if (this.isLoggedIn) return;

    this.apiKey = localStorage.getItem('apiKey') || undefined;

    if (!this.isLoggedIn) {
      this.clear();
      return;
    }

    const res = await fetch(`${ENV.apiURL}/me`, {
      headers: this.authorizationHeader,
    });

    if (!res.ok) {
      this.clear();
      localStorage.removeItem('apiKey');

      throw new LoginError();
    }

    const { uid, admin } = (await res.json()) as { uid: string; admin: boolean };

    this.uid = uid;
    this.isAdmin = admin;
  }

  clear() {
    this.apiKey = this.uid = this.isAdmin = this.proxyUid = undefined;
  }
}
