import { service } from '@ember/service';

import type { NextFn } from '@ember-data/request';
import type CurrentUserService from 'repository/services/current-user';

export default class AuthHandler {
  @service declare currentUser: CurrentUserService;

  request<T>(context: { request: { headers?: HeadersInit } }, next: NextFn<T>) {
    const headers = new Headers(context.request.headers);

    for (const [key, value] of Object.entries(this.currentUser.authorizationHeader)) {
      headers.set(key, value);
    }

    return next(Object.assign({}, context.request, { headers }));
  }
}
