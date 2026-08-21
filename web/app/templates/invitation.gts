import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { LinkTo } from '@ember/routing';
import { pageTitle } from 'ember-page-title';

import ENV from 'repository/config/environment';
import formatDatetime from 'repository/helpers/format-datetime';
import { stashInvitationToken } from 'repository/routes/invitation';
import { errorMessage } from 'repository/utils/error-message';
import { signUpURL } from 'repository/utils/runtime-config';

import type InvitationController from 'repository/controllers/invitation';
import type CurrentUserService from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';
import type { components } from 'schema/openapi';

type Invitation = components['schemas']['Invitation'];
type SetSummary = components['schemas']['SetSummary'];

interface Signature {
  Args: {
    model: {
      token: string;
      invitation: Invitation;
    };

    controller: InvitationController;
  };
}

// Where an invitation mail lands. Readable without a session, because the
// person holding it may not have a DDBJ Account yet and this page's job is
// to say what they are being invited to before it asks them to make one.
export default class extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  @tracked busy = false;
  @tracked error: string | null = null;

  authURL = ENV.authURL;

  get open() {
    return this.args.model.invitation.status === 'open';
  }

  // Somebody has already walked through this link — very likely the
  // reader themselves, from another device. Answered rather than hidden:
  // the token is kept after acceptance precisely so this page can say so.
  get used() {
    return this.args.model.invitation.status === 'accepted';
  }

  get expired() {
    return this.args.model.invitation.status === 'expired';
  }

  // Only while it is still true. It comes back on the URL, so after
  // logging in the reader would otherwise be told to log in below a Join
  // button.
  get justSignedUp() {
    return Boolean(this.args.controller.signedUp) && !this.currentUser.isLoggedIn && this.open;
  }

  get signUpURL() {
    const back = new URL(`${ENV.rootURL}invitation`, window.location.origin);
    back.searchParams.set('signed_up', '1');

    return signUpURL(back.toString());
  }

  // A full page load is about to happen, so the transition this route was
  // reached by will not survive it. The token is left here rather than
  // handed to DDBJ Account (see router.ts), and the address to come back
  // to goes where a 401 leaves one.
  @action
  leaveForSignUp() {
    stashInvitationToken(this.args.model.token);
  }

  @action
  rememberReturn() {
    this.currentUser.rememberReturn();
  }

  @action
  async accept() {
    if (this.busy) return;

    this.busy = true;
    this.error = null;

    try {
      const { content } = await this.requestManager.request<SetSummary>({
        url: `/invitations/${this.args.model.token}/acceptance`,
        method: 'POST',
        options: { reportErrors: false },
      });

      this.toast.show(`You have joined “${content.name}”.`, 'success');

      await this.router.transitionTo('set', content.id);
    } catch (e) {
      // On the page rather than in a modal: the two things that land here
      // — the link was used while this tab was open, or it lapsed — both
      // need the reader to read the page again, not to dismiss a dialog
      // over it.
      this.error = errorMessage(e) ?? 'Could not join. Try opening the link again.';
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{pageTitle "Invitation"}}

    <div class="row justify-content-center py-4">
      <div class="col-12 col-lg-7">
        <div class="eyebrow text-uppercase text-body-tertiary fw-semibold small mb-3">
          DDBJ Repository
        </div>

        <h1 class="display-6 mb-3">
          {{@model.invitation.invited_by}}
          has invited you to “{{@model.invitation.set_name}}”
        </h1>

        <p class="fs-5 text-body-secondary prose mb-4">
          A set is submissions that belong together — the ones behind a paper, a study, a piece of work. Everyone in the
          set can see what the others have put in it and how far along it is. Which of your own submissions go in stays
          your decision, and you can take them back out at any time.
        </p>

        {{#if this.justSignedUp}}
          <div class="alert alert-success">
            <p class="fw-semibold mb-1">Your DDBJ Account is ready.</p>
            <p class="mb-0 small">Log in below to join the set.</p>
          </div>
        {{/if}}

        {{#if this.error}}
          <div class="alert alert-warning" data-test-error>{{this.error}}</div>
        {{/if}}

        {{#if this.expired}}
          <div class="alert alert-warning">
            <p class="fw-semibold mb-1">This invitation has expired.</p>

            <p class="mb-0 small">
              Ask
              {{@model.invitation.invited_by}}
              — or anyone else in the set — to send it again. The new mail will come to
              {{@model.invitation.email}}.
            </p>
          </div>
        {{else if this.used}}
          <div class="alert alert-secondary">
            <p class="fw-semibold mb-1">This invitation has already been used.</p>

            <p class="mb-0 small">
              If that was you, the set is on
              <LinkTo @route="sets">your sets</LinkTo>. If it was not, ask
              {{@model.invitation.invited_by}}
              to send a new invitation to
              {{@model.invitation.email}}.
            </p>
          </div>
        {{else if this.currentUser.isLoggedIn}}
          <button
            type="button"
            class="btn btn-primary btn-lg"
            disabled={{this.busy}}
            data-test-join
            {{on "click" this.accept}}
          >
            Join
            {{@model.invitation.set_name}}
          </button>

          {{! Not `currentUser.user.uid` while a proxy is on: that is the
          curator's own account, and the server would refuse the write
          anyway — joining a set is a decision recorded against whoever
          made it. }}
          {{#if this.currentUser.isProxyLoggedIn}}
            <p class="text-warning-emphasis small mt-3 mb-0">
              You are acting as another account. End the proxy before joining a set.
            </p>
          {{else}}
            <p class="text-body-tertiary small mt-3 mb-0">
              You will join as
              {{this.currentUser.user.uid}}.
            </p>
          {{/if}}
        {{else}}
          <form action={{this.authURL}} method="POST" {{on "submit" this.rememberReturn}}>
            <button type="submit" class="btn btn-primary btn-lg" data-test-login>Log in with DDBJ Account</button>
          </form>

          {{#if this.signUpURL}}
            <p class="mt-4 mb-1 fw-semibold">Do not have a DDBJ Account?</p>

            <p class="text-body-secondary">
              <a href={{this.signUpURL}} data-test-sign-up {{on "click" this.leaveForSignUp}}>Create one</a>
              — you will be brought back to this page when it is ready.
            </p>
          {{/if}}

          <p class="text-body-tertiary small mt-3 mb-0">
            This invitation was sent to
            {{@model.invitation.email}}
            and is valid until
            {{formatDatetime @model.invitation.expires_at}}. You can accept it with any DDBJ Account; the set's roster
            will show which one you used.
          </p>
        {{/if}}
      </div>
    </div>
  </template>
}
