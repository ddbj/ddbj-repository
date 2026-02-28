import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import User from 'repository/models/user';

import type RequestManager from '@ember-data/request';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';
import type { paths } from 'schema/openapi';

type Me = paths['/me']['get']['responses']['200']['content']['application/json'];

export class LoginError extends Error {}

export default class CurrentUserService extends Service {
  @service declare requestManager: RequestManager;
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

    try {
      const { content } = await this.requestManager.request<Me>({
        url: '/me',
      });

      this.user = new User(content.uid, content.api_key, content.admin);
    } catch {
      this.clear();
      localStorage.removeItem('token');

      throw new LoginError();
    }
  }

  clear() {
    this.token = this.user = this.proxyUid = undefined;
  }
}
