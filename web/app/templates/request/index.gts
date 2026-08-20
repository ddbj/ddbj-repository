import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { concat } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import ProgressSteps from 'repository/components/progress-steps';
import ValidityBadge from 'repository/components/validity-badge';
import ValidationReport from 'repository/components/validation-report';
import SubmissionMessages from 'repository/components/submission-messages';
import ReviewerAccess from 'repository/components/reviewer-access';
import SetMembership from 'repository/components/set-membership';
import autoRefresh from 'repository/modifiers/auto-refresh';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';
import { requestState, stateLabel, toneClasses } from 'repository/utils/request-state';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type { components } from 'schema/openapi';

interface Signature {
  Args: {
    model: components['schemas']['SubmissionRequest'];
  };
}

// Answers "am I waiting, or is this on me?" before anything else, then
// how far along it is, then the conversation. The flat metadata list that
// used to open the page is folded away at the bottom — it is reference,
// not the reason anyone opens this screen.
export default class extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  get state() {
    return requestState(this.args.model);
  }

  // Only when the check found something that blocks sending. A report
  // above the fold on a request that passed would be answering a
  // question nobody asked.
  get failedCheck() {
    const { validation } = this.args.model;

    return validation?.validity === 'invalid' && validation.details.length > 0 ? validation : null;
  }

  get tone() {
    return toneClasses(this.state.tone);
  }

  // Closing and reopening are the same act in two directions, and the
  // response is the request itself, so both write it back the same way.
  @action
  async setClosed(closed: boolean) {
    const { model } = this.args;

    await this.requestManager.request({
      url: `/submission_requests/${model.id}/closure`,
      method: closed ? 'POST' : 'DELETE',
    });

    await this.router.refresh();
  }

  @action
  close() {
    return this.setClosed(true);
  }

  @action
  reopen() {
    return this.setClosed(false);
  }

  // What almost everyone does after a failed validation: fix the file and
  // send it again. Doing it in one press is what stops the old attempt
  // being left behind — a corrected file is a NEW request, so the failed
  // one is only ever closed by somebody remembering to come back for it.
  //
  // Closed first, then navigated: if the close fails the submitter stays
  // on the request that still needs it, rather than landing on an upload
  // form believing this one is dealt with.
  @action
  async closeAndResubmit() {
    await this.setClosed(true);

    this.router.transitionTo('db.requests.new', this.args.model.db);
  }

  @action
  async apply() {
    const { model } = this.args;

    await this.requestManager.request({
      url: `/submission_requests/${model.id}/submission`,
      method: 'POST',
    });

    await this.router.refresh();
  }

  <template>
    <div {{autoRefresh while=@model.processing interval=1000}}>
      {{! "My submissions" is where the reader's own list is. Somebody
      reading this through a shared set did not come from there and
      would not find it there either. }}
      {{#if @model.owned}}
        <Breadcrumb @items={{array (hash label="My submissions" route="index") (hash label=(concat "#" @model.id))}} />
      {{else}}
        <Breadcrumb @items={{array (hash label="Sets" route="sets") (hash label=(concat "#" @model.id))}} />
      {{/if}}

      <div class="d-flex align-items-baseline gap-2 flex-wrap mb-4">
        <h1 class="display-6 mb-0">#{{@model.id}}</h1>
        <span class="badge text-bg-light border">{{dbLabel @model.db}}</span>

        {{#if @model.submission.source_id}}
          <code class="text-body-secondary">{{@model.submission.source_id}}</code>
        {{/if}}

        {{#if @model.progress.row_count}}
          <span class="text-body-secondary">·
            {{@model.progress.row_count}}
            {{if (eq @model.progress.row_count 1) "record" "records"}}</span>
        {{/if}}

        <span class="text-body-secondary">· submitted {{formatDatetime @model.created_at}}</span>
      </div>

      {{! Every sentence in the panel below is written to the submitter —
      "your file is ready", "we will email you". Over an empty button
      row, read by a colleague, that is worse than saying nothing: the
      amber "Action needed" badge would tell them something is on them
      when nothing is. They get the same facts stated about somebody
      else, and the progress steps underneath say the rest. }}
      {{#unless @model.owned}}
        <section class="border rounded-3 p-4 mb-4" data-test-shared-state>
          <div class="d-flex align-items-center gap-2 mb-2">
            <span class="badge rounded-pill text-bg-light border">Shared with you</span>
          </div>

          <h2 class="h4">{{@model.owner_uid}}'s submission</h2>

          <p class="prose mb-1">
            You can see this because it is in a set you are both in. It is theirs to send, to answer questions on and to
            take back out of the set.
          </p>

          {{! Where it has got to, said about somebody rather than to them. }}
          <p class="text-body-secondary mb-0">{{stateLabel @model owned=false}}.</p>
        </section>
      {{/unless}}

      {{#if @model.owned}}
        <section class="border rounded-3 p-4 mb-4 {{this.tone.border}}" data-test-state>
          <div class="d-flex align-items-center gap-2 mb-2">
            <span class="badge rounded-pill {{this.tone.badge}}">{{this.state.badge}}</span>

            {{! When the thread was last touched — a fact. How long a reply
          takes is not something this system knows, so it does not say. }}
            {{#if @model.last_message_at}}
              <span class="small text-body-secondary">
                last message
                {{formatDatetime @model.last_message_at}}
              </span>
            {{/if}}
          </div>

          <h2 class="h4">{{this.state.heading}}</h2>
          <p class="prose mb-3">{{this.state.body}}</p>

          <div class="d-flex gap-2 flex-wrap">
            {{! Everything that acts on the request is withheld once it is
          closed. The status does not change when a request is put down,
          so a button gated on status alone stays on offer and then fails
          against a server that will not act on a closed request — and
          "Apply" beside "no longer waiting on you" is a contradiction
          before it is a broken button. Reopen is the way back, and it is
          what the panel above tells them to use. }}
            {{#unless @model.closed_at}}
              {{! "Send to DDBJ", not "Apply". There are two buttons in this
            flow and only one of them hands anything over; naming them
            after what they do to DDBJ rather than after the endpoint is
            what makes which is which readable. }}
              {{#if (eq @model.status "ready_to_apply")}}
                <button type="button" class="btn btn-primary" data-test-send {{on "click" this.apply}}>Send to DDBJ</button>
              {{/if}}

              {{! Only where there is nothing else to do with the file. On a
            request that validated, the next step is Apply, and a second
            primary button offering a fresh upload would compete with it. }}
              {{#if (eq @model.status "validation_failed")}}
                <button
                  type="button"
                  class="btn btn-primary"
                  data-test-close-and-resubmit
                  {{on "click" this.closeAndResubmit}}
                >Close and submit a corrected file</button>
              {{/if}}

              {{! A failed attempt cannot be advanced — a corrected file is a
            new request — so without this it asks to be dealt with for ever
            and crowds out the live one. Quiet, because it is the lesser of
            the two things on offer when both are. }}
              {{#if @model.closable}}
                <button type="button" class="btn btn-outline-secondary" data-test-close {{on "click" this.close}}>Close
                  this request</button>
              {{/if}}
            {{/unless}}

            {{#if @model.closed_at}}
              <button
                type="button"
                class="btn btn-outline-secondary"
                data-test-reopen
                {{on "click" this.reopen}}
              >Reopen</button>
            {{/if}}
          </div>
        </section>
      {{/if}}

      {{! A failed check is the one thing on this screen worth reading, so
      it is not folded away with the reference material at the bottom. A
      report that has to be opened before it says anything is a report
      nobody reads twice. }}
      {{! Its opening line is "this is still your draft — fix what is below",
      which is an instruction to the wrong person when a colleague is the
      one reading. What is on the screen for them is the state panel above
      and the steps below, both of which say what happened without telling
      them to do anything about it. }}
      {{#if @model.owned}}
        {{#if this.failedCheck}}
          <ValidationReport @validation={{this.failedCheck}} />
        {{/if}}
      {{/if}}

      <ProgressSteps @progress={{@model.progress}} />

      {{! The conversation is between one submitter and DDBJ. Reading
      somebody's submission through a shared set is not being party to
      it — the server withholds the messages, and offering the box would
      only produce a 404. }}
      {{#if @model.owned}}
        <SubmissionMessages @requestId={{@model.id}} />
      {{/if}}

      {{! Reference material. Present, but not in the way of the answer. }}
      {{! no-nested-interactive treats <details> as interactive and so
      rejects any link inside it. Links in disclosure *content* (as opposed
      to inside <summary>) are valid HTML and reachable by keyboard once
      the disclosure is open, which is exactly what these are. }}
      {{! template-lint-disable no-nested-interactive }}
      {{! A list group rather than a border utility on each row: Bootstrap's
      flush variant already draws the line between items and drops it
      after the last one, so the stack keeps its separators however many
      of these are on screen. Which varies — the sharing controls are the
      submitter's, and somebody reading through a set sees neither. }}
      <div class="mt-4 border-top list-group list-group-flush">
        {{! Only while the check passed. A failed one is reported above,
        said as work, and it carries this same table folded underneath
        itself — listing the findings twice on one screen makes the
        reader wonder which is the real one. }}
        {{#unless this.failedCheck}}
          {{#if @model.validation}}
            <details class="list-group-item px-0 py-3">
              <summary>
                Validation report
                <span class="text-body-secondary ms-2">
                  <ValidityBadge @validity={{@model.validation.validity}} />
                  {{#if @model.validation.details.length}}
                    {{@model.validation.details.length}}
                    findings
                  {{/if}}
                </span>
              </summary>

              <table class="table mt-3">
                <thead>
                  <tr>
                    <th>Entry ID</th>
                    <th>Code</th>
                    <th>Severity</th>
                    <th>Message</th>
                  </tr>
                </thead>

                <tbody>
                  {{#each @model.validation.details as |detail|}}
                    <tr>
                      <td>{{detail.entry_id}}</td>
                      <td>{{detail.code}}</td>
                      <td>{{detail.severity}}</td>
                      <td>{{detail.message}}</td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </details>
          {{/if}}
        {{/unless}}

        {{#if @model.submission}}
          <details class="list-group-item px-0 py-3">
            <summary>
              Accessions
              <span class="text-body-secondary ms-2">{{@model.submission.accessions_count}}</span>
            </summary>

            <p class="mt-3 mb-0">
              <LinkTo @route="request.accessions" @model={{@model.id}}>View all accessions</LinkTo>
            </p>
          </details>
        {{/if}}

        <details class="list-group-item px-0 py-3">
          <summary>Files &amp; downloads</summary>

          <dl class="horizontal mt-3">
            <dt>Uploaded file</dt>

            <dd>
              <a
                href={{@model.ddbj_record.url}}
                target="_blank"
                rel="noopener noreferrer"
              >{{@model.ddbj_record.filename}}</a>
            </dd>

            {{#if @model.submission}}
              <dt>DDBJ Record</dt>

              <dd>
                <a
                  href={{@model.submission.ddbj_record.url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >{{@model.submission.ddbj_record.filename}}</a>
              </dd>

              <dt>Flatfile (NA)</dt>

              <dd>
                {{#if @model.submission.flatfile_na}}
                  <a
                    href={{@model.submission.flatfile_na.url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >{{@model.submission.flatfile_na.filename}}</a>
                {{else}}
                  <span class="text-body-secondary">Not applicable</span>
                {{/if}}
              </dd>

              <dt>Flatfile (AA)</dt>

              <dd>
                {{#if @model.submission.flatfile_aa}}
                  <a
                    href={{@model.submission.flatfile_aa.url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >{{@model.submission.flatfile_aa.filename}}</a>
                {{else}}
                  <span class="text-body-secondary">Not applicable</span>
                {{/if}}
              </dd>
            {{/if}}
          </dl>
        </details>

        {{! Where a submission is shared, and who it is shared with, are the
        submitter's decisions. Somebody reading through a set sees the
        set they share on the set's own page. }}
        {{#if @model.owned}}
          <details class="list-group-item px-0 py-3">
            <summary>Sets</summary>

            <SetMembership @requestId={{@model.id}} @sets={{@model.sets}} />
          </details>

          <details class="list-group-item px-0 py-3">
            <summary>Share with a reviewer</summary>

            <ReviewerAccess @requestId={{@model.id}} />
          </details>
        {{/if}}
      </div>
    </div>
  </template>
}
