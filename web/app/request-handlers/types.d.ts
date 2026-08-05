import '@warp-drive/core/types/request';

type ScalarParam = string | number | boolean | null | undefined;

declare module '@warp-drive/core/types/request' {
  interface RequestInfo {
    options?: {
      params?: Record<string, ScalarParam | ScalarParam[]>;
    };
  }
}
