import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'repository/config/environment';
import convertCreatedToDate from 'repository/utils/convert-created-to-date';
import getLastPageFromLinkHeader from 'repository/utils/get-last-page-from-link-header';

import type RequestService from 'repository/services/request';
import type SubmissionsIndexController from 'repository/controllers/submissions';
import type { Created } from 'repository/models/criteria';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export interface Model {
  submissions: Submission[];
  lastPage: number;
}

interface Params {
  page?: number;
  db?: string;
  created?: Created;
}

export default class SubmissionsIndexRoute extends Route {
  @service declare request: RequestService;

  timer?: number;

  queryParams = {
    page: {
      refreshModel: true,
    },
    db: {
      refreshModel: true,
    },
    created: {
      refreshModel: true,
    },
  };

  async model(params: Params) {
    const url = new URL(`${ENV.apiURL}/submissions`);

    if (params.page !== undefined) {
      url.searchParams.set('page', params.page.toString());
    }

    if (params.db !== undefined) {
      url.searchParams.set('db', params.db);
    }

    if (params.created !== undefined) {
      url.searchParams.set('created_at_after', convertCreatedToDate(params.created).toISOString());
    }

    const res = await this.request.fetch(url.toString());

    return {
      submissions: (await res.json()) as Submission[],
      lastPage: getLastPageFromLinkHeader(res.headers.get('Link')),
    };
  }

  afterModel(model: Model) {
    if (model.submissions.some(({ progress }) => progress === 'waiting' || progress === 'running')) {
      this.timer = setTimeout(() => {
        this.refresh();
      }, 2000);
    }
  }

  resetController(controller: SubmissionsIndexController, isExiting: boolean) {
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
