import '@warp-drive/core/types/request';

type ScalarParam = string | number | boolean | null | undefined;

declare module '@warp-drive/core/types/request' {
  interface RequestInfo {
    options?: {
      params?: Record<string, ScalarParam | ScalarParam[]>;

      // False when the caller puts the failure on the screen itself. See
      // ErrorModalHandler: two reports of one failure, one of them a
      // modal over the page, is worse than either alone.
      reportErrors?: boolean;
    };
  }
}
