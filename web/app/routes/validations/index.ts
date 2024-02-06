import ValidationsIndexBaseRoute from 'ddbj-repository/routes/validations-index-base';

import { subDays, subWeeks, subMonths, subYears } from 'date-fns';

import ENV from 'ddbj-repository/config/environment';

import type { Created } from 'ddbj-repository/components/validations-search-form';

export interface Params {
  page?: number;
  db?: string;
  created?: Created;
  progress?: string;
  validity?: string;
  submitted?: boolean;
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

function convertCreatedToDate(created: NonNullable<Created>) {
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
      throw new Error(created satisfies never);
  }
}
