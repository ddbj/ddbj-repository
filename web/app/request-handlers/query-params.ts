import type { NextFn } from '@ember-data/request';

type ParamValue = string | number | boolean | null | undefined;

export default class QueryParamsHandler {
  request<T>(
    context: { request: { url?: string; options?: { params?: Record<string, ParamValue> } } },
    next: NextFn<T>,
  ) {
    const params = context.request.options?.params;

    if (params) {
      const searchParams = new URLSearchParams();

      for (const [key, value] of Object.entries(params)) {
        if (value != null) {
          searchParams.set(key, value.toString());
        }
      }

      const qs = searchParams.size ? `?${searchParams}` : '';

      return next({ ...context.request, url: `${context.request.url}${qs}` });
    }

    return next(context.request);
  }
}
