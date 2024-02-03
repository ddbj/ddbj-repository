import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';
import getLastPageFromLinkHeader from 'ddbj-repository/utils/get-last-page-from-link-header';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ValidationsIndexController from 'ddbj-repository/controllers/validations';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export interface Model {
  validations: Validation[];
  lastPage: number;
}

export default class ValidationsRoute extends Route {
  @service declare currentUser: CurrentUserService;

  timer?: number;

  queryParams = {
    page: {
      refreshModel: true,
    },
  };

  async model(params: { page?: string }) {
    const url = new URL(`${ENV.apiURL}/validations`);

    if (params.page) {
      url.searchParams.set('page', params.page);
    }

    const res = await fetch(url, {
      headers: this.currentUser.authorizationHeader,
    });

    if (!res.ok) {
      throw new Error(res.statusText);
    }

    return {
      validations: await res.json(),
      lastPage: getLastPageFromLinkHeader(res.headers.get('Link')),
    };
  }

  afterModel(model: Model) {
    if (model.validations.some(({ progress }) => progress === 'waiting' || progress === 'running')) {
      this.timer = setTimeout(() => {
        this.refresh();
      }, 2000);
    }
  }

  resetController(controller: ValidationsIndexController, isExiting: boolean) {
    if (isExiting) {
      controller.pageBefore = controller.page;
      controller.page = undefined;
    }
  }

  deactivate() {
    if (this.timer) {
      clearTimeout(this.timer);
    }
  }
}
