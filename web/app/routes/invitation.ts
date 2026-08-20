import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type Invitation = paths['/invitations/{token}']['get']['responses']['200']['content']['application/json'];

// Where the token waits while the reader is off creating an account. See
// router.ts: it is deliberately not in the URL handed to DDBJ Account.
export const INVITATION_TOKEN_KEY = 'invitationToken';

// The same window CurrentUserService gives `returnTo`, for the same
// reason: creating an account is a round trip somebody can simply
// abandon, and a token left in storage would otherwise resume an
// invitation nobody is in the middle of any more.
const INVITATION_TOKEN_TTL = 30 * 60 * 1000;

export function stashInvitationToken(token: string) {
  localStorage.setItem(INVITATION_TOKEN_KEY, JSON.stringify({ token, at: Date.now() }));
}

export function takeInvitationToken(): string | undefined {
  const raw = localStorage.getItem(INVITATION_TOKEN_KEY);
  localStorage.removeItem(INVITATION_TOKEN_KEY);

  if (!raw) return undefined;

  try {
    const { token, at } = JSON.parse(raw) as { token?: string; at?: number };

    if (!token || !at || Date.now() - at > INVITATION_TOKEN_TTL) return undefined;

    return token;
  } catch {
    return undefined;
  }
}

// No auth gate, deliberately. The person holding the link may not have a
// DDBJ Account yet, and this page's job is to tell them what they are
// being invited to before it asks them to make one.
export default class InvitationRoute extends Route {
  @service declare requestManager: RequestManager;

  async model({ token }: { token: string }) {
    const { content } = await this.requestManager.request<Invitation>({ url: `/invitations/${token}` });

    return { token, invitation: content };
  }
}
