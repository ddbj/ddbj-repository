import Route from '@ember/routing/route';
import { service } from '@ember/service';

import getLastPageFromLinkHeader from 'repository/utils/get-last-page-from-link-header';

import type RequestService from 'repository/services/request';
import type ValidationsIndexBaseController from 'repository/controllers/validations-index-base';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export interface Model {
  validations: Validation[];
  lastPage: number;
}

export default abstract class ValidationsIndexBaseRoute<TParams extends Record<string, unknown>> extends Route {
  @service declare request: RequestService;

  timer?: number;

  abstract buildURL(params: TParams): URL;

  async model(params: TParams) {
    const url = this.buildURL(params);
    const res = await this.request.fetch(url.toString());

    return {
      validations: (await res.json()) as Validation[],
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
