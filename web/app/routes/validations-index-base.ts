import Route from '@ember/routing/route';
import { service } from '@ember/service';

import getLastPageFromLinkHeader from 'ddbj-repository/utils/get-last-page-from-link-header';
import safeFetch from 'ddbj-repository/utils/safe-fetch';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ValidationsIndexBaseController from 'ddbj-repository/controllers/validations-index-base';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export interface Model {
  validations: Validation[];
  lastPage: number;
}

export default abstract class ValidationsIndexBaseRoute<TParams extends Record<string, unknown>> extends Route {
  @service declare currentUser: CurrentUserService;

  timer?: number;

  abstract buildURL(params: TParams): URL;

  async model(params: TParams) {
    const url = this.buildURL(params);

    const res = await safeFetch(url, {
      headers: this.currentUser.authorizationHeader,
    });

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

  resetController(controller: ValidationsIndexBaseController, isExiting: boolean) {
    if (isExiting) {
      controller.pageBefore = controller.page;
      controller.page = 1;
    }
  }

  deactivate() {
    if (this.timer) {
      clearTimeout(this.timer);
    }
  }
}
