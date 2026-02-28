import '@warp-drive/core/types/request';

declare module '@warp-drive/core/types/request' {
  interface RequestInfo {
    options?: {
      params?: Record<string, string | number | boolean | null | undefined>;
    };
  }
}
