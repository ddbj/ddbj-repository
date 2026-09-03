import Component from '@glimmer/component';
import { Textarea } from '@ember/component';
import { action } from '@ember/object';
import { fn, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';
import { errorMessage } from 'repository/utils/error-message';

import type { RequestManager } from '@warp-drive/core';
import type ToastService from 'repository/services/toast';
import type { components, paths } from 'schema/openapi';

type AccessState = paths['/sets/{set_id}/reviewer_access']['get']['responses']['200']['content']['application/json'];
type SharedAccession = components['schemas']['SharedAccession'];

type AddResult =
  paths['/sets/{set_id}/reviewer_access/accessions']['post']['responses']['200']['content']['application/json'];

type Preset = 'week' | 'month' | 'custom';

// Which of the two heavy controls is asking "are you sure".
type Confirmable = 'newLink' | 'revoke';

interface Signature {
  Args: {
    setId: number;
  };
}

// The set's review link: one URL, and the accessions the members have put
// on it.
//
// Two rules, and they are different on purpose. The link is any member's
// to mint and to revoke — waiting for one person to revoke a URL that has
// got out is the wrong way round. What it carries is not: each accession
// is put on and taken off by the owner of the submission it belongs to,
// which is why the rows without a Take-off button are somebody else's
// rather than locked.
export default class SetReviewerAccess extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare toast: ToastService;

  @tracked access: AccessState = { enabled: false, url: null, expires_at: null, expired: false, accessions: [] };
  @tracked preset: Preset = 'week';
  @tracked customDate = '';
  @tracked accessions = '';
  @tracked busy = false;
  @tracked confirming: Confirmable | null = null;

  // Errors land beside the control that caused them: the likely one here
  // is an accession that is not in the set, and what to do about it is to
  // fix the box it was typed into.
  @tracked linkError: string | null = null;
  @tracked accessionsError: string | null = null;

  constructor(owner: unknown, args: Signature['Args']) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);
    void this.load();
  }

  get endpoint() {
    return `/sets/${this.args.setId}/reviewer_access`;
  }

  get shared(): SharedAccession[] {
    return this.access.accessions;
  }

  // How much a Revoke would take with it, and how much of that is not the
  // presser's to take. Anybody in the set may revoke — waiting for one
  // person to kill a URL that has got out is the wrong way round — so the
  // button has to say what it costs before it fires.
  get theirs() {
    return this.shared.filter((a) => !a.owned).length;
  }

  // Custom expiry needs a date before the link can be minted.
  get enableDisabled() {
    return this.busy || (this.preset === 'custom' && !this.customDate);
  }

  get addDisabled() {
    return this.busy || this.parsed.length === 0;
  }

  // One per line is what somebody pasting out of a manuscript has, but a
  // comma-separated list is what they have as often — so both, rather
  // than a format to get right.
  get parsed() {
    return this.accessions.split(/[\s,]+/).filter(Boolean);
  }

  // Called outside `run`, never inside it: a re-read that fails after a
  // write that succeeded would otherwise put "that did not work" under the
  // accession box, about the one thing that did.
  async load() {
    const { content } = await this.requestManager.request<AccessState>({ url: this.endpoint });

    this.access = content;
  }

  expiresAtISO() {
    switch (this.preset) {
      case 'week': {
        return new Date(Date.now() + 7 * 86_400_000).toISOString();
      }
      case 'month': {
        const d = new Date();
        d.setMonth(d.getMonth() + 1);
        return d.toISOString();
      }
      case 'custom': {
        // The date input yields YYYY-MM-DD; treat it as the end of that day.
        return new Date(`${this.customDate}T23:59:59`).toISOString();
      }
    }
  }

  @action
  updatePreset(e: Event) {
    this.preset = (e.target as HTMLSelectElement).value as Preset;
  }

  @action
  updateCustomDate(e: Event) {
    this.customDate = (e.target as HTMLInputElement).value;
  }

  // Replacing a URL and revoking one are both irreversible and both leave
  // the building, so both ask first — and the asking is where the price is
  // named, because neither button can say it on its own.
  @action
  ask(what: Confirmable) {
    this.confirming = what;
  }

  @action
  cancel() {
    this.confirming = null;
  }

  @action
  async enable() {
    const replacing = this.access.enabled;

    const ok = await this.run(
      async () => {
        const { content } = await this.requestManager.request<AccessState>({
          url: this.endpoint,
          method: 'POST',
          data: { reviewer_access: { expires_at: this.expiresAtISO() } },
          options: { reportErrors: false },
        });

        this.access = content;
      },
      { onError: (m) => (this.linkError = m) },
    );

    if (!ok) return;

    this.confirming = null;
    this.toast.show(
      replacing
        ? 'A new link is in force. The previous URL no longer works; what is on it is unchanged.'
        : 'Review link enabled.',
      'success',
    );
  }

  @action
  async disable() {
    const taken = this.shared.length;

    const ok = await this.run(
      async () => {
        await this.requestManager.request({
          url: this.endpoint,
          method: 'DELETE',
          options: { reportErrors: false },
        });

        this.access = { enabled: false, url: null, expires_at: null, expired: false, accessions: [] };
      },
      { onError: (m) => (this.linkError = m) },
    );

    if (!ok) return;

    this.confirming = null;
    this.toast.show(
      taken > 0
        ? `Review link revoked, and ${taken} ${taken === 1 ? 'accession' : 'accessions'} taken off it.`
        : 'Review link revoked.',
      'success',
    );
  }

  @action
  async add(e: Event) {
    e.preventDefault();

    let added = 0;
    let already = 0;

    const ok = await this.run(
      async () => {
        const { content } = await this.requestManager.request<AddResult>({
          url: `${this.endpoint}/accessions`,
          method: 'POST',
          data: { accessions: this.parsed },
          options: { reportErrors: false },
        });

        added = content.added;
        already = content.already_shared;
        this.accessions = '';
      },
      { onError: (m) => (this.accessionsError = m) },
    );

    if (!ok) return;

    // Both numbers. "8 added" alone leaves somebody who pasted ten
    // wondering what happened to the other two.
    this.toast.show(
      already > 0 ? `${added} added; ${already} already on the link.` : `${added} added to the link.`,
      'success',
    );

    await this.load();
  }

  @action
  async remove(accession: string) {
    const ok = await this.run(
      async () => {
        await this.requestManager.request({
          url: `${this.endpoint}/accessions/${encodeURIComponent(accession)}`,
          method: 'DELETE',
          options: { reportErrors: false },
        });
      },
      { onError: (m) => (this.accessionsError = m) },
    );

    if (!ok) return;

    this.toast.show('Taken off the link.', 'success');

    await this.load();
  }

  @action
  async copy() {
    if (!this.access.url) return;

    await navigator.clipboard.writeText(this.access.url);
    this.toast.show('Link copied.', 'success');
  }

  // Answers whether the work went through, so a caller can leave what
  // follows it — a toast, a re-read — outside the `try` that is there to
  // catch the write.
  async run(work: () => Promise<void>, { onError }: { onError: (m: string) => void }) {
    if (this.busy) return false;

    this.busy = true;
    this.linkError = null;
    this.accessionsError = null;

    try {
      await work();

      return true;
    } catch (e) {
      onError(errorMessage(e) ?? 'That did not work. Try again.');

      return false;
    } finally {
      this.busy = false;
    }
  }

  <template>
    <section class="mb-5" data-test-reviewer-access>
      <h2 class="h4">Share with a reviewer</h2>

      <p class="text-body-secondary small">
        A link that shows named accessions to somebody without an account — a journal reviewer, say. Only the accessions
        put on it are visible, and each person adds their own. The submissions themselves, the files and this set's
        conversation are not shared.
      </p>

      {{#if this.linkError}}
        <div class="alert alert-warning" data-test-link-error>{{this.linkError}}</div>
      {{/if}}

      {{#if this.access.enabled}}
        <div class="mb-2">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="form-label">Share URL</label>

            <div class="input-group">
              <input id={{id}} type="text" class="form-control" readonly value={{this.access.url}} />
              <button type="button" class="btn btn-outline-secondary" {{on "click" this.copy}}>Copy</button>
            </div>
          {{/let}}
        </div>

        {{#if this.access.expired}}
          {{! Red, because this is a fact about the state rather than a
          doubt: the URL above answers 404 now. }}
          <p class="small text-danger">
            This link expired
            {{formatDatetime this.access.expires_at}}
            and no longer opens. Issue a new one below.
          </p>
        {{else}}
          <p class="small text-body-secondary">
            Stops working
            {{formatDatetime this.access.expires_at}}.
          </p>
        {{/if}}
      {{/if}}

      <div class="row g-2 align-items-end mb-3">
        <div class="col-auto">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="form-label">Expiry</label>

            <select id={{id}} class="form-select" {{on "change" this.updatePreset}}>
              <option value="week" selected={{eq this.preset "week"}}>1 week</option>
              <option value="month" selected={{eq this.preset "month"}}>1 month</option>
              <option value="custom" selected={{eq this.preset "custom"}}>Custom</option>
            </select>
          {{/let}}
        </div>

        {{#if (eq this.preset "custom")}}
          <div class="col-auto">
            {{#let (uniqueId) as |id|}}
              <label for={{id}} class="form-label">Date</label>
              <input
                id={{id}}
                type="date"
                class="form-control"
                value={{this.customDate}}
                {{on "change" this.updateCustomDate}}
              />
            {{/let}}
          </div>
        {{/if}}

        <div class="col-auto">
          {{! An unused link is one press; replacing one that is out there
          is not, so the second asks first. }}
          <button
            type="button"
            class="btn btn-primary"
            disabled={{this.enableDisabled}}
            {{on "click" (if this.access.enabled (fn this.ask "newLink") this.enable)}}
          >
            {{if this.access.enabled "New link" "Enable"}}
          </button>
        </div>

        {{#if this.access.enabled}}
          <div class="col-auto">
            {{! Amber, not red. Red says something about the data — this
            failed, this is overdue — and a control that competes with
            that reading wins the attention without carrying the meaning. }}
            <button type="button" class="btn btn-warning" disabled={{this.busy}} {{on "click" (fn this.ask "revoke")}}>
              Revoke
            </button>
          </div>
        {{/if}}
      </div>

      {{#if this.confirming}}
        <div class="border rounded p-3 mb-3" data-test-confirm>
          {{#if (eq this.confirming "newLink")}}
            <p class="mb-2">
              The URL above stops working, and anybody you have already sent it to loses access. What is on the link
              stays — it is not yours to take off.
            </p>

            <button type="button" class="btn btn-warning me-1" disabled={{this.busy}} {{on "click" this.enable}}>
              Replace the link
            </button>
          {{else}}
            <p class="mb-2">
              The link stops working and everything on it comes off —
              {{this.shared.length}}
              {{if (eq this.shared.length 1) "accession" "accessions"}}{{#if this.theirs}},
                {{this.theirs}}
                of them other people's{{/if}}. Issuing a new link afterwards starts it empty.
            </p>

            <button type="button" class="btn btn-warning me-1" disabled={{this.busy}} {{on "click" this.disable}}>
              Revoke and take off
              {{this.shared.length}}
            </button>
          {{/if}}

          <button type="button" class="btn btn-link" {{on "click" this.cancel}}>Cancel</button>
        </div>
      {{/if}}

      {{#if this.access.enabled}}
        {{#if this.shared}}
          <div class="table-responsive">
            <table class="table align-middle" data-test-shared>
              <thead>
                <tr>
                  <th scope="col">Accession</th>
                  <th scope="col">Database</th>
                  <th scope="col">Name</th>
                  <th scope="col">Owner</th>
                  <th scope="col"><span class="visually-hidden">Actions</span></th>
                </tr>
              </thead>

              <tbody>
                {{#each this.shared as |accession|}}
                  <tr>
                    <td class="font-monospace">{{accession.accession}}</td>
                    <td>{{dbLabel accession.db}}</td>

                    <td>
                      {{#if accession.name}}
                        {{accession.name}}
                      {{else}}
                        <span class="text-body-tertiary">—</span>
                      {{/if}}
                    </td>

                    <td class="text-body-secondary">{{accession.owner_uid}}</td>

                    <td class="text-end">
                      {{#if accession.owned}}
                        <button
                          type="button"
                          class="btn btn-outline-secondary btn-sm"
                          disabled={{this.busy}}
                          aria-label="Take {{accession.accession}} off the link"
                          {{on "click" (fn this.remove accession.accession)}}
                        >
                          Take off
                        </button>
                      {{/if}}
                    </td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{else}}
          <p class="text-body-secondary small">
            The link carries nothing yet, so anybody opening it sees an empty page.
          </p>
        {{/if}}

        <form {{on "submit" this.add}}>
          <div class="row g-2 align-items-end">
            <div class="col-sm-6 col-lg-4">
              {{#let (uniqueId) as |id|}}
                <label for={{id}} class="form-label">Accessions to share</label>

                {{! `<Textarea @value>` rather than a bare element: an
                HTML textarea whose content starts with a newline loses
                it, and a pasted list is exactly where that shows up. }}
                <Textarea
                  id={{id}}
                  class="form-control {{if this.accessionsError 'is-invalid'}}"
                  rows="3"
                  placeholder="PRJDB1234&#10;SAMD00000001"
                  @value={{this.accessions}}
                />

                {{#if this.accessionsError}}
                  <div class="invalid-feedback d-block" data-test-accessions-error>{{this.accessionsError}}</div>
                {{/if}}
              {{/let}}
            </div>

            <div class="col-auto">
              <button type="submit" class="btn btn-primary" disabled={{this.addDisabled}}>Add</button>
            </div>
          </div>

          <p class="form-text">
            One per line, or separated by commas. They have to be in this set already, and yours — a colleague's
            accession is theirs to put on.
          </p>
        </form>
      {{/if}}
    </section>
  </template>
}
