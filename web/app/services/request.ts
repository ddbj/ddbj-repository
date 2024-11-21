import Fetch from '@ember-data/request/fetch';
import RequestManager from '@ember-data/request';
import { service } from '@ember/service';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type { NextFn, RequestContext } from '@ember-data/request';

export default class RequestService extends RequestManager {
  @service declare currentUser: CurrentUserService;

  constructor(args) {
    super(args);

    this.use([
      {
        request: async <T>(context: RequestContext, nextFn: NextFn<T>) => {
          const headers = context.request.headers || new Headers();

          headers.set('Authorization', `Bearer ${this.currentUser.apiKey}`);

          return nextFn({
            ...context.request,
            headers,
          });
        },
      },
      Fetch,
    ]);
  }
}
