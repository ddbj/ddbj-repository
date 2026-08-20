import Route from '@ember/routing/route';
import { service } from '@ember/service';

import { takeInvitationToken } from 'repository/routes/invitation';

import type RouterService from '@ember/routing/router-service';

// The landing spot for a return from DDBJ Account. See router.ts for why
// the token is not in the URL that goes there — it is picked up from
// where the invitation page left it.
export default class InvitationResumeRoute extends Route {
  @service declare router: RouterService;

  beforeModel() {
    const token = takeInvitationToken();

    // Nothing waiting, or nothing recent enough. A bookmarked URL, or a
    // signup abandoned last month. The front page is a better answer than
    // an error: whoever this is either has an invitation mail to open or
    // has no business here.
    if (!token) return this.router.replaceWith('index');

    // `signedUp`, the controller's own property name — not `signed_up`,
    // which is only what it is called in the URL. Ember matches on the
    // former and silently ignores anything else.
    return this.router.replaceWith('invitation', token, { queryParams: { signedUp: '1' } });
  }
}
