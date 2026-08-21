import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { array, hash, uniqueId } from '@ember/helper';
import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';
import { errorMessage } from 'repository/utils/error-message';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';
import type { components } from 'schema/openapi';

type SetSummary = components['schemas']['SetSummary'];

interface Signature {
  Args: {
    model: SetSummary[];
  };
}

export default class extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  @tracked name = '';
  @tracked busy = false;
  @tracked error: string | null = null;

  get submitDisabled() {
    return this.busy || this.name.trim().length === 0;
  }

  @action
  updateName(e: Event) {
    this.name = (e.target as HTMLInputElement).value;
  }

  @action
  async create(e: Event) {
    e.preventDefault();

    if (this.submitDisabled) return;

    this.busy = true;
    this.error = null;

    try {
      const { content } = await this.requestManager.request<SetSummary>({
        url: '/sets',
        method: 'POST',
        data: { set: { name: this.name.trim() } },
        options: { reportErrors: false },
      });

      this.name = '';
      this.toast.show('Set created.', 'success');

      await this.router.transitionTo('set', content.id);
    } catch (e) {
      // On the field, not in a modal over the page: what lands here is
      // about the value still sitting in the box.
      this.error = errorMessage(e) ?? 'Could not create the set. Try again.';
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{pageTitle "Sets"}}

    <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="Sets")}} />

    <h1 class="display-6 mb-3">Sets</h1>

    <p class="text-body-secondary prose mb-4">
      A set is submissions that belong together — the ones behind a paper, a study, a piece of work — and the people
      they belong to. Everyone in a set can see the submissions in it and how far along they are, and each set has one
      conversation with DDBJ about the whole of it. What goes in stays each person's own decision.
    </p>

    {{#if @model.length}}
      <div class="list-group mb-4" data-test-sets>
        {{#each @model as |set|}}
          <LinkTo @route="set" @model={{set.id}} class="list-group-item list-group-item-action">
            <div class="d-flex justify-content-between align-items-start">
              <div>
                <div class="fw-semibold">
                  {{set.name}}

                  {{! Red because it is a fact about the data — somebody
                  is waiting on this set and nobody in it has answered. }}
                  {{#if set.unread_message_count}}
                    <span class="badge text-bg-danger ms-1" data-test-unread>
                      {{set.unread_message_count}}
                      {{if (eq set.unread_message_count 1) "message" "messages"}}
                    </span>
                  {{/if}}
                </div>

                <div class="small text-body-secondary">
                  Created by
                  {{set.owner_uid}}
                </div>
              </div>

              <div class="text-end small text-body-secondary">
                <div>{{set.member_count}} {{if (eq set.member_count 1) "member" "members"}}</div>
                <div>{{set.submission_count}} {{if (eq set.submission_count 1) "submission" "submissions"}}</div>

                {{#if set.invited_count}}
                  <div>{{set.invited_count}} invited</div>
                {{/if}}
              </div>
            </div>
          </LinkTo>
        {{/each}}
      </div>
    {{else}}
      {{! First run rather than a filtered empty: nothing has ever been
      here, so the words are about what will appear and how to start. }}
      <div class="border rounded p-4 mb-4 text-center">
        <p class="mb-1 fw-semibold">You are not in any set yet.</p>

        <p class="text-body-secondary small mb-0">
          Make one below, then invite the people you are working with and add your submissions to it.
        </p>
      </div>
    {{/if}}

    <form {{on "submit" this.create}}>
      <div class="row g-2 align-items-end">
        <div class="col-sm-6 col-lg-4">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="form-label">New set</label>

            <input
              id={{id}}
              type="text"
              class="form-control {{if this.error 'is-invalid'}}"
              placeholder="e.g. Deep sea metagenome 2026"
              value={{this.name}}
              {{on "input" this.updateName}}
            />

            {{#if this.error}}
              <div class="invalid-feedback d-block" data-test-error>{{this.error}}</div>
            {{/if}}
          {{/let}}
        </div>

        <div class="col-auto">
          <button type="submit" class="btn btn-primary" disabled={{this.submitDisabled}}>Create</button>
        </div>
      </div>
    </form>
  </template>
}
