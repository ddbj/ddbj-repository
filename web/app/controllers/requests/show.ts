import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class RequestsShowController extends Controller {
  @service declare currentUser: CurrentUserService;

  @action
  async downloadFile(url: string) {
    const res = await fetch(url, {
      headers: {
        Authorization: `Bearer ${this.currentUser.apiKey}`,
      },
    });

    location.href = res.url;
  }
}
