import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type Router from '@ember/routing/router';

export default class SubmitController extends Controller {
  @service declare currentUser: CurrentUserService;
  @service declare router: Router;

  dbs = ENV.dbs;

  @tracked selectedDb = this.dbs[0];

  @action
  async submit(e: Event) {
    e.preventDefault();

    const formData = new FormData(e.target as HTMLFormElement);

    for (const obj of this.selectedDb!.objects) {
      const prefix = obj.multiple ? `${obj.id}[]` : obj.id;
      const key = (attr: string) => `${prefix}[${attr}]`;

      const path = formData.get(key('path'));

      if (path === '') {
        formData.delete(key('path'));
      }

      if (!formData.has(key('file')) || !path || path === '') {
        formData.delete(key('destination'));
      }
    }

    const url = `${ENV.apiURL}/${formData.get('resource')}/${this.selectedDb!.id.toLowerCase()}/via-file`;

    const res = await fetch(url, {
      method: 'POST',

      headers: {
        Authorization: `Bearer ${this.currentUser.apiKey}`,
      },

      body: formData,
    });

    const { request } = await res.json();

    this.router.transitionTo('requests.show', request.id);
  }
}
