import ValidationsIndexBaseRoute from 'ddbj-repository/routes/validations-index-base';

import ENV from 'ddbj-repository/config/environment';
import convertCreatedToDate from 'ddbj-repository/utils/convert-created-to-date';

import type { Created } from 'ddbj-repository/components/validations-search-form';

export interface Params {
  page?: number;
  db?: string;
  created?: Created;
  progress?: string;
  validity?: string;
  submitted?: boolean;
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
