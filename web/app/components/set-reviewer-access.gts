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
type SetAccession = components['schemas']['SetAccession'];

type AddResult =
  paths['/sets/{set_id}/reviewer_access/accessions']['post']['responses']['200']['content']['application/json'];

interface Signature {
  Args: {
    setId: number;
  };
}

type Preset = 'week' | 'month' | 'custom';

// Which of the heavy controls is asking "are you sure".
type Confirmable = 'newLink' | 'revoke' | 'shareAll';

const NO_LINK: AccessState = {
  enabled: false,
  url: null,
  expires_at: null,
  expired: false,
  count: 0,
  others: 0,
};

// Prev/Next rather than the routed pager: these lists live inside a
// component on the set's own screen, so a page of one of them is not a
// place the browser goes.
class Pager extends Component<{
  Args: { page: number; pages: number; busy: boolean; label: string; go: (page: number) => void };
}> {
  get atStart() {
    return this.args.page <= 1;
  }

  get atEnd() {
    return this.args.page >= this.args.pages;
  }

  @action
  first() {
    this.args.go(1);
  }

  @action
  previous() {
    this.args.go(this.args.page - 1);
  }

  @action
  next() {
    this.args.go(this.args.page + 1);
  }

  @action
  last() {
    this.args.go(this.args.pages);
  }

  <template>
    {{#if (gt @pages 1)}}
      <nav class="d-flex align-items-center gap-2 mb-3" aria-label="Pages of {{@label}}">
        {{! Both ends, not only the neighbours. These lists are as long as
        what the members submitted, and stepping to page 5,000 one press
        at a time is not a way back to the end of a list. }}
        <button
          type="button"
          class="btn btn-outline-secondary btn-sm"
          disabled={{if this.atStart true @busy}}
          aria-label="First page of {{@label}}"
          {{on "click" this.first}}
        >
          «
        </button>

        <button
          type="button"
          class="btn btn-outline-secondary btn-sm"
          disabled={{if this.atStart true @busy}}
          aria-label="Previous page of {{@label}}"
          {{on "click" this.previous}}
        >
          Previous
        </button>

        <span class="small text-body-secondary">Page {{@page}} of {{@pages}}</span>

        <button
          type="button"
          class="btn btn-outline-secondary btn-sm"
          disabled={{if this.atEnd true @busy}}
          aria-label="Next page of {{@label}}"
          {{on "click" this.next}}
        >
          Next
        </button>

        <button
          type="button"
          class="btn btn-outline-secondary btn-sm"
          disabled={{if this.atEnd true @busy}}
          aria-label="Last page of {{@label}}"
          {{on "click" this.last}}
        >
          »
        </button>
      </nav>
    {{/if}}
  </template>
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
//
// Every list here is a page of one, and none of the counts is derived
// from what is on screen. What a set holds has no ceiling — a BioSample
// submission alone can carry a hundred thousand samples — so "how many
// would this take off" is a number the server says, not one this counts.
export default class SetReviewerAccess extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare toast: ToastService;

  @tracked access: AccessState = NO_LINK;
  @tracked preset: Preset = 'week';
  @tracked customDate = '';
  @tracked accessions = '';
  @tracked busy = false;
  @tracked confirming: Confirmable | null = null;

  // What is on the link, a page at a time.
  @tracked shared: SharedAccession[] = [];
  @tracked sharedPage = 1;
  @tracked sharedPages = 1;

  // What could go on it — the reader's own accessions in the set. Behind a
  // press because it is a second request for something a submitter who
  // knows their numbers never opens.
  @tracked mine: SetAccession[] = [];
  @tracked minePage = 1;
  @tracked minePages = 1;
  @tracked mineTotal = 0;
  @tracked browsing = false;

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

  // Custom expiry needs a date before the link can be minted.
  get enableDisabled() {
    return this.busy || (this.preset === 'custom' && !this.customDate);
  }

  get addDisabled() {
    return this.busy || this.parsed.length === 0;
  }

  // One per line is what somebody pasting out of a manuscript has, but a
  // comma-separated list is what they have as often — so both, rather
  // than a format to get right. A range is one entry, not two.
  get parsed() {
    return this.accessions.split(/[\s,]+/).filter(Boolean);
  }

  // Called outside `run`, never inside it: a re-read that fails after a
  // write that succeeded would otherwise put "that did not work" under the
  // accession box, about the one thing that did.
  async load() {
    const { content } = await this.requestManager.request<AccessState>({ url: this.endpoint });

    this.access = content;

    if (content.enabled) {
      await this.loadShared(this.sharedPage);
    } else {
      this.shared = [];
      this.sharedPages = 1;
    }

    if (this.browsing) await this.loadMine(this.minePage);
  }

  async loadShared(page: number) {
    const { content, response } = await this.requestManager.request<SharedAccession[]>({
      url: `${this.endpoint}/accessions`,
      options: { params: { page }, reportErrors: false },
    });

    this.shared = content;
    this.sharedPage = page;
    this.sharedPages = Number(response?.headers?.get('Total-Pages')) || 1;
  }

  async loadMine(page: number) {
    const { content, response } = await this.requestManager.request<SetAccession[]>({
      url: `/sets/${this.args.setId}/accessions`,
      options: { params: { page }, reportErrors: false },
    });

    this.mine = content;
    this.minePage = page;
    this.minePages = Number(response?.headers?.get('Total-Pages')) || 1;
    this.mineTotal = Number(response?.headers?.get('Total-Count')) || 0;
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

  // Three presses that ask first, for two different reasons. Replacing a
  // URL and revoking one are irreversible and leave the building, so they
  // are amber. Sharing everything is undoable a row at a time and stays
  // primary — what it needs said is not "are you sure" but how many, and
  // a button cannot count on its own.
  // The two that are confirmed beside the link's own buttons. "Share
  // all" is confirmed at the foot of the browse list instead, where the
  // button that opens it is.
  get confirmingLink() {
    return this.confirming === 'newLink' || this.confirming === 'revoke';
  }

  @action
  ask(what: Confirmable) {
    this.confirming = what;
  }

  @action
  cancel() {
    this.confirming = null;
  }

  @action
  async browse() {
    this.browsing = true;

    await this.run(() => this.loadMine(1), { onError: (m) => (this.accessionsError = m) });
  }

  // One row, from the browse list. The same press as typing its number
  // into the box, which is why it goes the same way.
  @action
  shareOne(accession: string) {
    return this.share({ accessions: [accession] });
  }

  // Through `run` like every other request in this component: paging is
  // the one that can be pressed twice in a second, so without `busy` two
  // overlapping reads race and the last one back decides both the rows
  // and the page number they are labelled with.
  @action
  async goShared(page: number) {
    await this.run(() => this.loadShared(page), { onError: (m) => (this.accessionsError = m) });
  }

  @action
  async goMine(page: number) {
    await this.run(() => this.loadMine(page), { onError: (m) => (this.accessionsError = m) });
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

    // The POST answered with the link, so there is nothing to re-read
    // about it. What it does not carry is the list — replacing a URL
    // leaves that alone, and enabling a first one starts it empty.
    await this.loadShared(1);
  }

  @action
  async disable() {
    const taken = this.access.count;

    const ok = await this.run(
      async () => {
        await this.requestManager.request({
          url: this.endpoint,
          method: 'DELETE',
          options: { reportErrors: false },
        });

        this.access = NO_LINK;
        this.shared = [];
        this.sharedPage = 1;
        this.sharedPages = 1;
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
  add(e: Event) {
    e.preventDefault();

    return this.share({ accessions: this.parsed });
  }

  @action
  shareAll() {
    return this.share({ all: true });
  }

  // The two forms differ only in what is posted; what happens afterwards —
  // the counts, the re-read — is the same press either way.
  async share(data: { accessions: string[] } | { all: true }) {
    let added = 0;
    let already = 0;

    const ok = await this.run(
      async () => {
        const { content } = await this.requestManager.request<AddResult>({
          url: `${this.endpoint}/accessions`,
          method: 'POST',
          data,
          options: { reportErrors: false },
        });

        added = content.added;
        already = content.already_shared;

        if ('accessions' in data) this.accessions = '';
      },
      { onError: (m) => (this.accessionsError = m) },
    );

    if (!ok) return;

    this.confirming = null;

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

    // Back a page if that was the last row on the last page, so taking the
    // final accession off does not leave somebody looking at an empty
    // page 3 wondering where their list went.
    if (this.shared.length === 1 && this.sharedPage > 1) this.sharedPage -= 1;

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

      {{! Only the two that belong beside the buttons above. A
      confirmation renders where the control that opened it is — the
      "Share all" one is at the foot of the browse list, and putting it
      here left somebody pressing a button and watching nothing happen,
      because the panel was two tables above the fold. }}
      {{#if this.confirmingLink}}
        <div class="border rounded p-3 mb-3" data-test-confirm>
          {{#if (eq this.confirming "newLink")}}
            <p class="mb-2">
              The URL above stops working, and anybody you have already sent it to loses access. What is on the link
              stays — it is not yours to take off.
            </p>

            <button
              type="button"
              class="btn btn-warning me-1"
              disabled={{this.busy}}
              data-test-confirm-action
              {{on "click" this.enable}}
            >
              Replace the link
            </button>
          {{else}}
            <p class="mb-2">
              The link stops working and everything on it comes off —
              {{this.access.count}}
              {{if (eq this.access.count 1) "accession" "accessions"}}{{#if this.access.others}},
                {{this.access.others}}
                of them other people's{{/if}}. Issuing a new link afterwards starts it empty.
            </p>

            <button
              type="button"
              class="btn btn-warning me-1"
              disabled={{this.busy}}
              data-test-confirm-action
              {{on "click" this.disable}}
            >
              Revoke and take off
              {{this.access.count}}
            </button>
          {{/if}}

          <button type="button" class="btn btn-link" {{on "click" this.cancel}}>Cancel</button>
        </div>
      {{/if}}

      {{#if this.access.enabled}}
        {{#if this.shared}}
          {{! "Put on", not "is on": the count is of rows named on the
          link, and a row whose submission has since left the set is
          still named without being shown. }}
          <p class="small text-body-secondary mb-1" data-test-shared-count>
            {{this.access.count}}
            {{if (eq this.access.count 1) "accession has" "accessions have"}}
            been put on this link.
          </p>

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

        {{else if this.access.count}}
          {{! Reachable without anybody doing anything wrong: the rows are
          resolved through the set on every read, so a page can empty
          while somebody is looking at it. The pager below is how they get
          back, which is why it is outside this branch. }}
          <p class="text-body-secondary small">
            Nothing on this page. The submissions these accessions belong to may have left the set.
          </p>
        {{else}}
          <p class="text-body-secondary small">
            The link carries nothing yet, so anybody opening it sees an empty page.
          </p>
        {{/if}}

        <Pager
          @page={{this.sharedPage}}
          @pages={{this.sharedPages}}
          @busy={{this.busy}}
          @go={{this.goShared}}
          @label="what is on the link"
        />

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
                  placeholder="PRJDB1234&#10;SAMD00000001-SAMD00000050"
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
            One per line, or separated by commas. A first and a last with a hyphen between them —
            <code>SAMD00000001-SAMD00000050</code>
            — shares whichever of yours fall inside, which is how you share a block except the last few. They have to be
            in this set already, and yours: a colleague's accession is theirs to put on.
          </p>
        </form>

        {{! Behind a press: a submitter who has their numbers to hand never
        opens it, and it is a second request. }}
        {{#if this.browsing}}
          <div class="mt-3" data-test-mine>
            <p class="small text-body-secondary mb-1">
              You have
              {{this.mineTotal}}
              {{if (eq this.mineTotal 1) "accession" "accessions"}}
              in this set.
            </p>

            <div class="table-responsive">
              <table class="table table-sm align-middle">
                <thead>
                  <tr>
                    <th scope="col">Accession</th>
                    <th scope="col">Database</th>
                    <th scope="col">Name</th>
                    <th scope="col"><span class="visually-hidden">Actions</span></th>
                  </tr>
                </thead>

                <tbody>
                  {{#each this.mine as |accession|}}
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

                      <td class="text-end">
                        {{#if accession.shared}}
                          <span class="text-body-secondary small">On the link</span>
                        {{else}}
                          <button
                            type="button"
                            class="btn btn-outline-secondary btn-sm"
                            disabled={{this.busy}}
                            aria-label="Put {{accession.accession}} on the link"
                            {{on "click" (fn this.shareOne accession.accession)}}
                          >
                            Share
                          </button>
                        {{/if}}
                      </td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>

            <Pager
              @page={{this.minePage}}
              @pages={{this.minePages}}
              @busy={{this.busy}}
              @go={{this.goMine}}
              @label="your accessions"
            />

            {{! Nothing to put on the link is not a press to offer. }}
            {{#if this.mineTotal}}
              <button
                type="button"
                class="btn btn-outline-primary btn-sm"
                disabled={{this.busy}}
                data-test-share-all
                {{on "click" (fn this.ask "shareAll")}}
              >
                Share all
                {{this.mineTotal}}
              </button>
            {{/if}}

            {{#if (eq this.confirming "shareAll")}}
              <div class="border rounded p-3 mt-2" data-test-confirm>
                <p class="mb-2">
                  Everything of yours in this set —
                  {{this.mineTotal}}
                  {{if (eq this.mineTotal 1) "accession" "accessions"}}
                  — goes on the link, and anybody holding the URL can read them. You can take any of them off again
                  afterwards.
                </p>

                <button
                  type="button"
                  class="btn btn-primary me-1"
                  disabled={{this.busy}}
                  data-test-confirm-action
                  {{on "click" this.shareAll}}
                >
                  Put all
                  {{this.mineTotal}}
                  on the link
                </button>

                <button type="button" class="btn btn-link" {{on "click" this.cancel}}>Cancel</button>
              </div>
            {{/if}}
          </div>
        {{else}}
          <button type="button" class="btn btn-link px-0" {{on "click" this.browse}} data-test-browse>
            Show my accessions in this set
          </button>
        {{/if}}
      {{/if}}
    </section>
  </template>
}
