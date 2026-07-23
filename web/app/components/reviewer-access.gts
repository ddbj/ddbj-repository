import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { uniqueId } from '@ember/helper';

import formatDatetime from 'repository/helpers/format-datetime';

import type { RequestManager } from '@warp-drive/core';
import type ToastService from 'repository/services/toast';
import type { paths } from 'schema/openapi';

type AccessState =
  paths['/submission_requests/{submission_request_id}/reviewer_access']['get']['responses']['200']['content']['application/json'];

type Preset = 'week' | 'month' | 'custom';

interface Signature {
  Args: {
    requestId: number;
  };
}

// Submitter control for the shareable reviewer link. Enabling posts an
// expiry timestamp (computed from a preset or a custom date) and shows the
// generated URL; re-enabling mints a fresh link.
export default class ReviewerAccess extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare toast: ToastService;

  @tracked url?: string;
  @tracked expiresAt: string | null = null;
  @tracked preset: Preset = 'week';
  @tracked customDate = '';
  @tracked busy = false;

  constructor(owner: unknown, args: Signature['Args']) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);
    void this.load();
  }

  get enabled() {
    return Boolean(this.url);
  }

  // Custom expiry needs a date before the link can be minted.
  get submitDisabled() {
    return this.busy || (this.preset === 'custom' && !this.customDate);
  }

  get endpoint() {
    return `/submission_requests/${this.args.requestId}/reviewer_access`;
  }

  async load() {
    const { content } = await this.requestManager.request<AccessState>({ url: this.endpoint });

    this.apply(content);
  }

  apply(access: AccessState) {
    this.url = access.enabled ? access.url : undefined;
    this.expiresAt = access.enabled ? (access.expires_at ?? null) : null;
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

  @action
  async enable() {
    if (this.busy) return;
    if (this.preset === 'custom' && !this.customDate) return;

    this.busy = true;

    try {
      const { content } = await this.requestManager.request<AccessState>({
        url: this.endpoint,
        method: 'POST',
        data: { reviewer_access: { expires_at: this.expiresAtISO() } },
      });

      this.apply(content);
      this.toast.show('Reviewer access enabled.', 'success');
    } finally {
      this.busy = false;
    }
  }

  @action
  async disable() {
    if (this.busy) return;

    this.busy = true;

    try {
      await this.requestManager.request({ url: this.endpoint, method: 'DELETE' });

      this.url = undefined;
      this.expiresAt = null;
      this.toast.show('Reviewer access disabled.', 'success');
    } finally {
      this.busy = false;
    }
  }

  @action
  async copy() {
    if (!this.url) return;

    await navigator.clipboard.writeText(this.url);
    this.toast.show('Link copied.', 'success');
  }

  <template>
    <section class="mt-4">
      <h2 class="h4">Reviewer access</h2>

      <p class="text-body-secondary small">
        Share a read-only link that lets a reviewer view this request without logging in. Messages are not shown to
        reviewers.
      </p>

      {{#if this.enabled}}
        <div class="mb-2">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="form-label">Share URL</label>

            <div class="input-group">
              <input id={{id}} type="text" class="form-control" readonly value={{this.url}} />
              <button type="button" class="btn btn-outline-secondary" {{on "click" this.copy}}>Copy</button>
            </div>
          {{/let}}
        </div>

        <p class="small text-body-secondary">
          Expires
          {{formatDatetime this.expiresAt}}.
        </p>
      {{/if}}

      <div class="row g-2 align-items-end">
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
          <button type="button" class="btn btn-primary" disabled={{this.submitDisabled}} {{on "click" this.enable}}>
            {{if this.enabled "Regenerate" "Enable"}}
          </button>
        </div>

        {{#if this.enabled}}
          <div class="col-auto">
            <button type="button" class="btn btn-outline-danger" disabled={{this.busy}} {{on "click" this.disable}}>
              Disable
            </button>
          </div>
        {{/if}}
      </div>
    </section>
  </template>
}
