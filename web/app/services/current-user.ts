import Service, { service } from '@ember/service';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

import User from 'repository/models/user';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';
import type ToastService from 'repository/services/toast';
import type { paths } from 'schema/openapi';

type Me = paths['/me']['get']['responses']['200']['content']['application/json'];

export class LoginError extends Error {}

// Long enough for an OAuth round trip that includes making an account,
// short enough that an abandoned one does not redirect a login tomorrow.
const RETURN_TO_TTL = 30 * 60 * 1000;

export default class CurrentUserService extends Service {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  @tracked token?: string;
  @tracked user?: User;
  @tracked proxyUid?: string;

  // Set when a request came back 401 — the session ended somewhere else
  // (logged out in another tab, admin flag revoked, proxy ended). Drives a
  // banner rather than a modal: there is no session expiry here, so this
  // is rare, and covering the screen a curator is mid-edit on is the only
  // part of it that actually costs them something.
  @tracked sessionExpired = false;

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

  // A 401 means the token is no longer good, whatever the tab thinks.
  // The URL is remembered across the OAuth round trip (a full page load,
  // so component state does not survive) to make "you will come back to
  // this page" true.
  expireSession() {
    if (this.sessionExpired) return;

    this.rememberReturn();
    localStorage.removeItem('token');

    this.clear();
    this.sessionExpired = true;
  }

  // Where to come back to after a full page load takes us out to the
  // identity provider. Stamped, because the round trip is one somebody
  // can simply abandon — close the tab, give up and go make an account —
  // and an address left in storage would otherwise hijack an unrelated
  // login days later, landing it on a page that may not even exist any
  // more.
  rememberReturn(url: string = this.router.currentURL ?? '/') {
    localStorage.setItem('returnTo', JSON.stringify({ url, at: Date.now() }));
  }

  takeReturn(): string | undefined {
    const raw = localStorage.getItem('returnTo');
    localStorage.removeItem('returnTo');

    if (!raw) return undefined;

    try {
      const { url, at } = JSON.parse(raw) as { url?: string; at?: number };

      if (!url || !at || Date.now() - at > RETURN_TO_TTL) return undefined;

      return url;
    } catch {
      return undefined;
    }
  }

  async login(token: string, proxyUid?: string) {
    this.clear();
    this.sessionExpired = false;
    localStorage.setItem('token', token);

    await this.restore();

    // Proxy-login hands the admin's token plus a target uid in one hop
    // (see Admin::ProxyLoginsController); start acting as the target here,
    // after the token is in place.
    if (proxyUid) {
      this.startProxy(proxyUid);
    }

    const returnTo = this.takeReturn();

    if (this.previousTransition) {
      this.previousTransition.retry();
      this.previousTransition = undefined;
    } else if (returnTo) {
      // Recorded before a 401 sent us out to the identity provider.
      this.router.transitionTo(returnTo);
    } else {
      this.router.transitionTo('index');
    }
  }

  logout() {
    // The web session is just the JWT in localStorage (stateless, no
    // server-side session to clear — that's the admin's cookie, which is
    // now independent). Clearing local state is the whole logout.
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
