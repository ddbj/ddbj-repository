import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { array, concat, fn, hash, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';
import Pagination from 'repository/components/pagination';
import SetMessages from 'repository/components/set-messages';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';
import { requestState, stateLabel, toneClasses } from 'repository/utils/request-state';
import { errorMessage } from 'repository/utils/error-message';

import type SetController from 'repository/controllers/set';
import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';
import type { components } from 'schema/openapi';

type Set = components['schemas']['Set'];
type Member = components['schemas']['SetMember'];
type SetSubmission = components['schemas']['SetSubmission'];

interface Signature {
  Args: {
    model: {
      set: Set;
      totalPages: number;
    };

    controller: SetController;
  };
}

const entryLabel = (entry: SetSubmission) => stateLabel(entry.submission, { owned: entry.owned });
const stateBadgeClass = (entry: SetSubmission) => toneClasses(requestState(entry.submission).tone).badge;

const submissionLabel = (entry: SetSubmission) => entry.submission.source_id ?? `#${entry.submission.id}`;

export default class extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  @tracked email = '';
  @tracked busy = false;

  // Errors land on the form that caused them, not in a modal over the
  // page: the likely ones here — "is already a member of this set", a
  // duplicate name — are about the value still sitting in the box.
  @tracked inviteError: string | null = null;
  @tracked pageError: string | null = null;

  // Which row is asking "are you sure", and how much goes with it.
  // Removing somebody takes their submissions out of the set, and
  // nothing else on this screen says so.
  @tracked confirming: number | null = null;
  @tracked confirmingCount = 0;

  @tracked renaming = false;
  @tracked name = '';

  // Not `set`: Ember's classic object model owns `this.set()`, and an
  // Octane class must not shadow it.
  get submissionSet() {
    return this.args.model.set;
  }

  get inviteDisabled() {
    return this.busy || this.email.trim().length === 0;
  }

  get joinedCount() {
    return this.submissionSet.members.filter((member) => member.status === 'accepted').length;
  }

  // Both from the server. Neither can be worked out here any more: the
  // submissions on screen are one page of however many there are, so
  // counting them would tell somebody "0 submissions" while the removal
  // took sixty out — and the wording of the reason belongs with the rule.
  get deleteHint() {
    return this.submissionSet.delete_blocked_reason ?? undefined;
  }

  // Disabled with the reason beside it, rather than hidden. An owner with
  // one forgotten invitation would otherwise see a set with, apparently,
  // no way to get rid of it — and a button that is offered and always
  // fails is no better.
  get deleteDisabled() {
    return this.busy || !this.submissionSet.deletable;
  }

  @action
  updateEmail(e: Event) {
    this.email = (e.target as HTMLInputElement).value;
  }

  @action
  updateName(e: Event) {
    this.name = (e.target as HTMLInputElement).value;
  }

  @action
  startRename() {
    this.name = this.submissionSet.name;
    this.renaming = true;
  }

  @action
  cancelRename() {
    this.renaming = false;
  }

  @action
  async rename(e: Event) {
    e.preventDefault();

    const name = this.name.trim();
    if (!name || name === this.submissionSet.name) return this.cancelRename();

    await this.run(async () => {
      await this.requestManager.request({
        url: `/sets/${this.submissionSet.id}`,
        method: 'PATCH',
        data: { set: { name } },
        options: { reportErrors: false },
      });

      this.renaming = false;
      this.toast.show('Set renamed.', 'success');
    });
  }

  @action
  async invite(e: Event) {
    e.preventDefault();

    if (this.inviteDisabled) return;

    this.inviteError = null;

    await this.run(
      async () => {
        const { content } = await this.requestManager.request<Member>({
          url: `/sets/${this.submissionSet.id}/members`,
          method: 'POST',
          data: { set_member: { email: this.email.trim() } },
          options: { reportErrors: false },
        });

        this.email = '';

        // Not "Invitation sent" when the answer just said it was not.
        // The roster carries the same fact and the link to send by hand;
        // the toast must not contradict the row it is about to draw.
        this.toast.show(
          content.mail_deliverable === false
            ? 'Invitation created. Mail is not being sent from this environment — copy the link from the list below.'
            : 'Invitation sent.',
          'success',
        );
      },
      { onError: (m) => (this.inviteError = m) },
    );
  }

  @action
  async resend(member: Member) {
    await this.run(async () => {
      await this.requestManager.request({
        url: `/sets/${this.submissionSet.id}/members/${member.id}/reminder`,
        method: 'POST',
        options: { reportErrors: false },
      });

      this.toast.show('Invitation sent again. The previous link no longer works.', 'success');
    });
  }

  @action
  askToRemove(member: Member) {
    this.confirming = member.id;
    this.confirmingCount = member.submission_count;
  }

  @action
  cancelRemove() {
    this.confirming = null;
    this.confirmingCount = 0;
  }

  @action
  async removeMember(member: Member) {
    await this.run(
      async () => {
        await this.requestManager.request({
          url: `/sets/${this.submissionSet.id}/members/${member.id}`,
          method: 'DELETE',
          options: { reportErrors: false },
        });

        this.confirming = null;
        this.toast.show(member.you ? 'You have left the set.' : 'Member removed.', 'success');
      },
      { leaving: member.you },
    );
  }

  @action
  async removeSubmission(entry: SetSubmission) {
    await this.run(async () => {
      await this.requestManager.request({
        url: `/sets/${this.submissionSet.id}/submissions/${entry.submission.id}`,
        method: 'DELETE',
        options: { reportErrors: false },
      });

      this.toast.show('Taken out of the set.', 'success');
    });
  }

  @action
  async deleteSet() {
    await this.run(
      async () => {
        await this.requestManager.request({
          url: `/sets/${this.submissionSet.id}`,
          method: 'DELETE',
          options: { reportErrors: false },
        });

        this.toast.show('Set deleted.', 'success');
      },
      { leaving: true },
    );
  }

  @action
  async copyInvitation(member: Member) {
    if (!member.invitation_url) return;

    await navigator.clipboard.writeText(member.invitation_url);
    this.toast.show('Invitation link copied.', 'success');
  }

  // Every write here changes what the page is showing — who is on the
  // roster, what is in the set — so the page is re-read rather than
  // patched in six different ways. Leaving is the exception: the page is
  // no longer readable by the person who just left.
  async run(
    work: () => Promise<void>,
    { leaving = false, onError = undefined as ((m: string) => void) | undefined } = {},
  ) {
    if (this.busy) return;

    this.busy = true;
    this.pageError = null;

    try {
      await work();

      await (leaving ? this.router.transitionTo('sets') : this.router.refresh());
    } catch (e) {
      const text = errorMessage(e) ?? 'That did not work. Try again.';

      (onError ?? ((m: string) => (this.pageError = m)))(text);
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{pageTitle this.submissionSet.name}}

    <Breadcrumb
      @items={{array
        (hash label="Home" route="index")
        (hash label="Sets" route="sets")
        (hash label=this.submissionSet.name)
      }}
    />

    <div class="d-flex justify-content-between align-items-start gap-3 mb-4">
      <div class="flex-grow-1">
        {{#if this.renaming}}
          <form class="row g-2 align-items-end" {{on "submit" this.rename}}>
            <div class="col-sm-6">
              {{#let (uniqueId) as |id|}}
                <label for={{id}} class="form-label">Set name</label>
                <input id={{id}} type="text" class="form-control" value={{this.name}} {{on "input" this.updateName}} />
              {{/let}}
            </div>

            <div class="col-auto">
              <button type="submit" class="btn btn-primary" disabled={{this.busy}}>Save</button>
            </div>

            <div class="col-auto">
              <button type="button" class="btn btn-link" {{on "click" this.cancelRename}}>Cancel</button>
            </div>
          </form>
        {{else}}
          <h1 class="display-6 mb-1">
            {{this.submissionSet.name}}

            {{#if this.submissionSet.owned}}
              <button
                type="button"
                class="btn btn-link align-baseline p-0 ms-2 fs-6"
                data-test-rename
                {{on "click" this.startRename}}
              >Rename</button>
            {{/if}}
          </h1>

          <p class="text-body-secondary small mb-0">
            Created by
            {{this.submissionSet.owner_uid}}
            on
            {{formatDatetime this.submissionSet.created_at}}
          </p>
        {{/if}}
      </div>

      {{#if this.submissionSet.owned}}
        <div class="text-end">
          <button
            type="button"
            class="btn btn-warning"
            disabled={{this.deleteDisabled}}
            title={{this.deleteHint}}
            data-test-delete
            {{on "click" this.deleteSet}}
          >
            Delete set
          </button>

          {{#if this.deleteHint}}
            <p class="form-text mb-0 delete-hint">{{this.deleteHint}}</p>
          {{/if}}
        </div>
      {{/if}}
    </div>

    {{#if this.pageError}}
      <div class="alert alert-warning" data-test-error>{{this.pageError}}</div>
    {{/if}}

    <section class="mb-5" data-test-members>
      <h2 class="h4">People</h2>

      <p class="text-body-secondary small">
        Everyone here can see the submissions in this set. Anyone can invite; each person decides which of their own
        submissions to put in, and removing somebody takes theirs out with them.
      </p>

      <div class="table-responsive mb-3">
        <table class="table align-middle">
          <thead>
            <tr>
              <th scope="col">Account</th>
              <th scope="col">Invited to</th>
              <th scope="col">State</th>
              <th scope="col"><span class="visually-hidden">Actions</span></th>
            </tr>
          </thead>

          <tbody>
            {{#each this.submissionSet.members as |member|}}
              <tr>
                <td>
                  {{#if member.uid}}
                    {{member.uid}}
                  {{else}}
                    <span class="text-body-secondary">—</span>
                  {{/if}}

                  {{#if member.owner}}
                    <span class="badge text-bg-secondary ms-1">owner</span>
                  {{/if}}

                  {{#if member.you}}
                    <span class="badge text-bg-secondary ms-1">you</span>
                  {{/if}}
                </td>

                <td class="text-body-secondary">
                  {{#if member.email}}
                    {{member.email}}
                  {{else}}
                    <span class="text-body-tertiary">—</span>
                  {{/if}}

                  {{#if (eq member.invited_address_match "different")}}
                    {{! Not an error. Somebody forwarded the invitation, or
                    the account is registered elsewhere — either way the
                    roster is where it gets seen rather than guessed at. }}
                    <div class="small text-warning-emphasis">
                      Accepted by an account registered at a different address.
                    </div>
                  {{else if (eq member.invited_address_match "unknown")}}
                    <div class="small text-body-secondary">
                      That account has no address on file, so this could not be checked.
                    </div>
                  {{/if}}

                  {{#if (eq member.mail_deliverable false)}}
                    <div class="small text-warning-emphasis">
                      Mail to this address is not being sent from this environment. Send them the link instead.
                    </div>
                  {{/if}}
                </td>

                <td>
                  {{#if (eq member.status "accepted")}}
                    <span class="text-body-secondary small">Joined {{formatDatetime member.joined_at}}</span>
                  {{else if (eq member.status "expired")}}
                    <span class="badge text-bg-danger">Invitation expired</span>
                  {{else}}
                    <span class="badge text-bg-secondary">Invited</span>
                    <div class="small text-body-secondary">
                      until
                      {{formatDatetime member.invitation_expires_at}}
                    </div>
                  {{/if}}
                </td>

                <td class="text-end">
                  {{#if (eq this.confirming member.id)}}
                    <div class="small text-body-secondary mb-1">
                      {{#if member.you}}
                        Leave this set?
                      {{else}}
                        Remove
                        {{if member.uid member.uid member.email}}?
                      {{/if}}

                      {{#if this.confirmingCount}}
                        {{if member.you "Your" "Their"}}
                        {{this.confirmingCount}}
                        {{if (eq this.confirmingCount 1) "submission" "submissions"}}
                        will be taken out of the set.
                      {{/if}}
                    </div>

                    <button
                      type="button"
                      class="btn btn-warning btn-sm me-1"
                      disabled={{this.busy}}
                      {{on "click" (fn this.removeMember member)}}
                    >
                      {{if member.you "Leave" "Remove"}}
                    </button>

                    <button type="button" class="btn btn-link btn-sm" {{on "click" this.cancelRemove}}>Cancel</button>
                  {{else}}
                    {{#unless (eq member.status "accepted")}}
                      <button
                        type="button"
                        class="btn btn-outline-secondary btn-sm me-1"
                        disabled={{this.busy}}
                        aria-label={{concat "Copy the invitation link for " member.email}}
                        {{on "click" (fn this.copyInvitation member)}}
                      >
                        Copy link
                      </button>

                      <button
                        type="button"
                        class="btn btn-outline-secondary btn-sm me-1"
                        disabled={{this.busy}}
                        aria-label={{concat "Send the invitation to " member.email " again"}}
                        {{on "click" (fn this.resend member)}}
                      >
                        Send again
                      </button>
                    {{/unless}}

                    {{#if member.removable}}
                      <button
                        type="button"
                        class="btn btn-outline-secondary btn-sm"
                        disabled={{this.busy}}
                        aria-label={{if
                          member.you
                          "Leave this set"
                          (concat "Remove " (if member.uid member.uid member.email))
                        }}
                        {{on "click" (fn this.askToRemove member)}}
                      >
                        {{if member.you "Leave" "Remove"}}
                      </button>
                    {{/if}}
                  {{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      </div>

      <form {{on "submit" this.invite}}>
        <div class="row g-2 align-items-end">
          <div class="col-sm-6 col-lg-4">
            {{#let (uniqueId) as |id|}}
              <label for={{id}} class="form-label">Invite by email</label>

              <input
                id={{id}}
                type="email"
                class="form-control {{if this.inviteError 'is-invalid'}}"
                placeholder="colleague@example.org"
                value={{this.email}}
                {{on "input" this.updateEmail}}
              />

              {{#if this.inviteError}}
                <div class="invalid-feedback d-block" data-test-invite-error>{{this.inviteError}}</div>
              {{/if}}
            {{/let}}
          </div>

          <div class="col-auto">
            <button type="submit" class="btn btn-primary" disabled={{this.inviteDisabled}}>Invite</button>
          </div>
        </div>

        <p class="form-text">
          They do not need a DDBJ Account yet — the mail explains how to make one. Nothing is shared with them until
          they open the link.
        </p>
      </form>
    </section>

    <section data-test-submissions>
      <h2 class="h4">Submissions</h2>

      {{#if this.submissionSet.submission_count}}
        <div class="table-responsive">
          <table class="table align-middle">
            <thead>
              <tr>
                <th scope="col">Submission</th>
                <th scope="col">Database</th>
                <th scope="col">Owner</th>
                <th scope="col">State</th>
                <th scope="col"><span class="visually-hidden">Actions</span></th>
              </tr>
            </thead>

            <tbody>
              {{#each this.submissionSet.submissions as |entry|}}
                <tr>
                  <td>
                    <LinkTo @route="request" @model={{entry.submission.id}}>{{submissionLabel entry}}</LinkTo>

                    {{#if entry.submission.first_accession}}
                      <div class="small text-body-secondary">
                        {{entry.submission.first_accession}}
                        {{#if (gt entry.submission.accession_count 1)}}
                          ({{entry.submission.accession_count}}
                          accessions)
                        {{/if}}
                      </div>
                    {{/if}}
                  </td>

                  <td>{{dbLabel entry.submission.db}}</td>
                  <td>{{entry.owner_uid}}</td>

                  <td>
                    <span class="badge {{stateBadgeClass entry}}">{{entryLabel entry}}</span>
                  </td>

                  <td class="text-end">
                    {{#if entry.owned}}
                      <button
                        type="button"
                        class="btn btn-outline-secondary btn-sm"
                        disabled={{this.busy}}
                        aria-label={{concat "Take " (submissionLabel entry) " out of this set"}}
                        {{on "click" (fn this.removeSubmission entry)}}
                      >
                        Take out
                      </button>
                    {{/if}}
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>

        <Pagination
          @route="set"
          @models={{array this.submissionSet.id}}
          @current={{@controller.page}}
          @total={{@model.totalPages}}
        />
      {{else}}
        <div class="border rounded p-4 text-center">
          <p class="mb-1 fw-semibold">Nothing has been put in this set yet.</p>

          <p class="text-body-secondary small mb-0">
            Tick them on
            <LinkTo @route="index">your submissions</LinkTo>
            and add them from there, or open one and add it from its own page. Putting a submission in a set is its
            owner's own decision, so each person adds their own.
          </p>
        </div>
      {{/if}}
    </section>

    {{! The set's own conversation, below what it holds — the thread is
    about the bundle, so it reads after the bundle. }}
    <SetMessages @setId={{this.submissionSet.id}} @unreadCount={{this.submissionSet.unread_message_count}} />
  </template>
}
