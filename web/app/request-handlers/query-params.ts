import type { NextFn } from '@ember-data/request';

type ScalarParam = string | number | boolean | null | undefined;
type ParamValue = ScalarParam | ScalarParam[];

export default class QueryParamsHandler {
  request<T>(
    context: { request: { url?: string; options?: { params?: Record<string, ParamValue> } } },
    next: NextFn<T>,
  ) {
    const params = context.request.options?.params;

    if (params) {
      const searchParams = new URLSearchParams();

      for (const [key, value] of Object.entries(params)) {
        if (Array.isArray(value)) {
          // Rails parses repeated `key[]=` occurrences into an array.
          for (const item of value) {
            if (item != null) searchParams.append(`${key}[]`, item.toString());
          }
        } else if (value != null) {
          searchParams.set(key, value.toString());
        }
      }

      const qs = searchParams.size ? `?${searchParams}` : '';

      return next({ ...context.request, url: `${context.request.url}${qs}` });
    }

    return next(context.request);
  }
}
