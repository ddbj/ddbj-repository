import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import User from 'repository/models/user';

import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';

export class LoginError extends Error {}

export default class CurrentUserService extends Service {
  @service declare request: RequestService;
  @service declare router: RouterService;

  @tracked token?: string;
  @tracked user?: User;
  @tracked proxyUid?: string;

  previousTransition?: Transition;

  get isLoggedIn() {
    return Boolean(this.token);
  }

  get isProxyLoggedIn() {
    return Boolean(this.proxyUid);
  }

  get authorizationHeader() {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.token}`,
    };

    if (this.proxyUid) {
      headers['X-Dway-User-Id'] = this.proxyUid;
    }

    return headers;
  }

  ensureLogin(transition: Transition, requireAdmin = false) {
    if (requireAdmin) {
      if (this.isLoggedIn && this.user?.isAdmin) return;
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

  async login(token: string) {
    this.clear();
    localStorage.setItem('token', token);

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
    localStorage.removeItem('token');

    this.router.transitionTo('index');
  }

  async restore() {
    if (this.isLoggedIn) return;

    this.token = localStorage.getItem('token') || undefined;

    if (!this.isLoggedIn) {
      this.clear();
      return;
    }

    let res: Response;

    try {
      res = await this.request.fetchWithModal('/me');
    } catch {
      this.clear();
      localStorage.removeItem('token');

      throw new LoginError();
    }

    const { uid, api_key, admin } = (await res.json()) as {
      uid: string;
      api_key: string;
      admin: boolean;
    };

    this.user = new User(uid, api_key, admin);
  }

  clear() {
    this.token = this.user = this.proxyUid = undefined;
  }
}
