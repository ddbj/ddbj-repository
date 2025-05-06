import ValidationsIndexBaseRoute from 'repository/routes/validations-index-base';

import ENV from 'repository/config/environment';
import convertCreatedToDate from 'repository/utils/convert-created-to-date';

import type { Created, Submitted } from 'repository/models/criteria';

export interface Params {
  page?: number;
  db?: string;
  created?: Created;
  progress?: string;
  validity?: string;
  submitted?: Submitted;
  [key: string]: unknown;
}

export const queryParams = {
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

  validity: {
    refreshModel: true,
  },

  submitted: {
    refreshModel: true,
  },
};

export default class ValidationsIndexRoute extends ValidationsIndexBaseRoute<Params> {
  queryParams = queryParams;

  buildURL(params: Params) {
    const url = new URL(`${ENV.apiURL}/validations`);

    if (params.page !== undefined) {
      url.searchParams.set('page', params.page.toString());
    }

    if (params.db !== undefined) {
      url.searchParams.set('db', params.db);
    }

    if (params.created !== undefined) {
      url.searchParams.set('created_at_after', convertCreatedToDate(params.created).toISOString());
    }

    if (params.progress !== undefined) {
      url.searchParams.set('progress', params.progress);
    }

    if (params.validity !== undefined) {
      url.searchParams.set('validity', params.validity);
    }

    if (params.submitted !== undefined) {
      url.searchParams.set('submitted', params.submitted.toString());
    }

    return url;
  }
}
