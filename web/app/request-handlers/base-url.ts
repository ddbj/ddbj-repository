import ENV from 'repository/config/environment';

import type { NextFn } from '@warp-drive/core/request';

export default class BaseURLHandler {
  request<T>(context: { request: { url?: string } }, next: NextFn<T>) {
    const { url } = context.request;

    if (url?.startsWith('/')) {
      return next(Object.assign({}, context.request, { url: `${ENV.apiURL}${url}` }));
    }

    return next(context.request);
  }
}
