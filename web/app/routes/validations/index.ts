import Route from '@ember/routing/route';
import { service } from '@ember/service';

import { subDays, subWeeks, subMonths, subYears } from 'date-fns';

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

interface Params {
  page?: string;
  db?: string;
  created?: string;
  progress?: string;
}

export default class ValidationsRoute extends Route {
  @service declare currentUser: CurrentUserService;

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
    progress: {
      refreshModel: true,
    },
  };

  async model(params: Params) {
    const url = new URL(`${ENV.apiURL}/validations`);

    if (params.page) {
      url.searchParams.set('page', params.page);
    }

    if (params.db) {
      url.searchParams.set('db', params.db);
    }

    if (params.created) {
      url.searchParams.set('created_at_after', convertCreatedToDate(params.created).toISOString());
    }

    if (params.progress) {
      url.searchParams.set('progress', params.progress);
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

function convertCreatedToDate(created: string) {
  const now = new Date();

  switch (created) {
    case 'within_one_day':
      return subDays(now, 1);
    case 'within_one_week':
      return subWeeks(now, 1);
    case 'within_one_month':
      return subMonths(now, 1);
    case 'within_one_year':
      return subYears(now, 1);
    default:
      throw new Error(created);
  }
}
