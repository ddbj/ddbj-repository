import ValidationsIndexBaseRoute from 'repository/routes/validations-index-base';
import ValidationsIndexRoute, { queryParams } from 'repository/routes/validations/index';

import type { Params as ParamsForUser } from 'repository/routes/validations/index';

interface Params extends ParamsForUser {
  uid?: string;
}

export default class AdminValidationsIndexRoute extends ValidationsIndexBaseRoute<Params> {
  queryParams = {
    ...queryParams,

    uid: {
      refreshModel: true,
    },
  };

  buildURL(params: Params) {
    const url = ValidationsIndexRoute.prototype.buildURL(params);

    url.searchParams.set('everyone', 'true');

    if (params.uid !== undefined) {
      url.searchParams.set('uid', params.uid);
    }

    return url;
  }
}
