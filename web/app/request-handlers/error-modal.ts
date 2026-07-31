import { service } from '@ember/service';

import type { NextFn, RequestContext } from '@ember-data/request';
import type CurrentUserService from 'repository/services/current-user';
import type ErrorModalService from 'repository/services/error-modal';

export default class ErrorModalHandler {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;

  async request<T>(context: RequestContext, next: NextFn<T>) {
    try {
      return await next(context.request);
    } catch (e) {
      // 401 is not an error to report, it is a state to be in: the session
      // ended somewhere else and the person has to log in again. A modal
      // would cover the screen they were working on in order to say so —
      // the banner says the same thing without taking the page away.
      if (status(e) === 401) {
        this.currentUser.expireSession();
      } else {
        this.errorModal.show(e as Error);
      }

      throw e;
    }
  }
}

function status(error: unknown): number | undefined {
  return (error as { status?: number } | undefined)?.status;
}
