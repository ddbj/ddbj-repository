import RequestManager from '@ember-data/request';
import Fetch from '@ember-data/request/fetch';
import { getOwner, setOwner } from '@ember/owner';

import AuthHandler from 'repository/request-handlers/auth';
import BaseURLHandler from 'repository/request-handlers/base-url';
import ErrorModalHandler from 'repository/request-handlers/error-modal';
import JsonBodyHandler from 'repository/request-handlers/json-body';
import QueryParamsHandler from 'repository/request-handlers/query-params';

export default {
  create(args: object) {
    const owner = getOwner(args)!;

    const errorModalHandler = new ErrorModalHandler();
    setOwner(errorModalHandler, owner);

    const authHandler = new AuthHandler();
    setOwner(authHandler, owner);

    return new RequestManager().use([
      errorModalHandler,
      new QueryParamsHandler(),
      new JsonBodyHandler(),
      new BaseURLHandler(),
      authHandler,
      Fetch,
    ]);
  },
};
