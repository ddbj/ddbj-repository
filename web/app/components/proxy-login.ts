import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class ProxyLoginComponent extends Component {
  @service declare currentUser: CurrentUserService;

  @tracked uid?: string;

  constructor(owner: unknown, args: object) {
    super(owner, args);

    this.uid = this.currentUser.proxyUid;
  }

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

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ProxyLogin: typeof ProxyLoginComponent;
  }
}
