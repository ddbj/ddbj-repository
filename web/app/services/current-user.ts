import Service, { service } from '@ember/service';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

import ENV from 'repository/config/environment';
import User from 'repository/models/user';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';
import type ToastService from 'repository/services/toast';
import type { paths } from 'schema/openapi';

type Me = paths['/me']['get']['responses']['200']['content']['application/json'];

export class LoginError extends Error {}

export default class CurrentUserService extends Service {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;
  @service declare toast: ToastService;

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

  isProxyLoggedInAs(uid: string) {
    return this.proxyUid === uid;
  }

  @action
  startProxy(uid: string) {
    this.proxyUid = uid;

    this.toast.show(`Proxy login as ${uid}.`, 'success');
  }

  @action
  stopProxy() {
    this.proxyUid = undefined;

    this.toast.show('Proxy login deactivated.', 'success');
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

  ensureLogin(transition: Transition) {
    if (this.isLoggedIn) return;

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

  async logout() {
    this.clear();
    localStorage.removeItem('token');

    // /session is outside /api, so RequestManager's BaseURLHandler wouldn't
    // route it; AuthHandler would also attach a stale bearer token.
    const sessionUrl = `${ENV.appURL}/session`;

    try {
      // eslint-disable-next-line warp-drive/no-external-request-patterns
      await fetch(sessionUrl, { method: 'DELETE', credentials: 'include' });
    } catch {
      // Network failures are non-fatal: local state is already cleared.
    }

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
