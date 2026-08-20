import Component from '@glimmer/component';
import { action } from '@ember/object';
import { concat } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { uniqueId } from '@ember/helper';
import { LinkTo } from '@ember/routing';

import { errorMessage } from 'repository/utils/error-message';

import type { RequestManager } from '@warp-drive/core';
import type ToastService from 'repository/services/toast';
import type { paths } from 'schema/openapi';

type Sets = paths['/sets']['get']['responses']['200']['content']['application/json'];
type Result = paths['/sets/{set_id}/submissions']['post']['responses']['200']['content']['application/json'];

interface Signature {
  Args: {
    submissionRequestIds: number[];
    onDone: () => void;
  };
}

// Putting a screenful of submissions into one set in a press.
//
// The alternative is opening each submission and adding it from its own
// page, which is the right place for the decision but the wrong place for
// ten of them: a set that is one paper's worth of work is ten round trips
// to assemble.
//
// Only what is on the page, deliberately. Selection that survives
// paging is selection somebody has forgotten about, and this writes to
// other people's screens.
export default class BulkAddToSet extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare toast: ToastService;

  @tracked mine: Sets = [];
  @tracked selected = '';
  @tracked busy = false;
  @tracked error: string | null = null;
  @tracked loaded = false;

  constructor(owner: unknown, args: Signature['Args']) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);

    // Swallowed: the list is a convenience above a working table, and a
    // modal because it could not be fetched would take the screen away
    // from what the reader came for.
    void this.load().catch(() => {});
  }

  async load() {
    const { content } = await this.requestManager.request<Sets>({ url: '/sets' });

    this.mine = content;
    this.loaded = true;
  }

  get count() {
    return this.args.submissionRequestIds.length;
  }

  get addDisabled() {
    return this.busy || !this.selected || this.count === 0;
  }

  @action
  updateSelected(e: Event) {
    this.selected = (e.target as HTMLSelectElement).value;
  }

  @action
  async add() {
    if (this.addDisabled) return;

    this.busy = true;
    this.error = null;

    try {
      const { content } = await this.requestManager.request<Result>({
        url: `/sets/${this.selected}/submissions`,
        method: 'POST',
        data: { submission_request_ids: this.args.submissionRequestIds },
      });

      // Both numbers. "8 added" alone leaves somebody who ticked ten
      // wondering what happened to the other two.
      this.toast.show(
        content.already_in_set > 0
          ? `${added(content.added)} to the set. ${content.already_in_set} ${
              content.already_in_set === 1 ? 'was' : 'were'
            } already in it.`
          : `${added(content.added)} to the set.`,
        'success',
      );

      this.selected = '';
      this.args.onDone();
    } catch (e) {
      this.error = errorMessage(e) ?? 'Could not add them to that set. Try again.';
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{#if this.count}}
      <div class="card mb-3" data-test-bulk-add>
        <div class="card-body py-2">
          {{#if this.loaded}}
            {{#if this.mine.length}}
              <div class="row g-2 align-items-center">
                <div class="col-auto fw-semibold">
                  {{this.count}}
                  selected on this page
                </div>

                <div class="col-auto">
                  {{#let (uniqueId) as |id|}}
                    <label for={{id}} class="visually-hidden">Add them to</label>

                    <select id={{id}} class="form-select form-select-sm" {{on "change" this.updateSelected}}>
                      <option value="">Add them to a set…</option>

                      {{#each this.mine as |set|}}
                        <option value={{set.id}} selected={{eq (concat set.id) this.selected}}>{{set.name}}</option>
                      {{/each}}
                    </select>
                  {{/let}}
                </div>

                <div class="col-auto">
                  <button
                    type="button"
                    class="btn btn-primary btn-sm"
                    disabled={{this.addDisabled}}
                    {{on "click" this.add}}
                  >
                    Add
                  </button>
                </div>

                <div class="col-auto">
                  <button type="button" class="btn btn-link btn-sm" {{on "click" @onDone}}>Clear</button>
                </div>
              </div>
            {{else}}
              <div class="small text-body-secondary">
                {{this.count}}
                selected on this page.
                <LinkTo @route="sets">Create a set</LinkTo>
                to put them in one.
              </div>
            {{/if}}
          {{/if}}

          {{#if this.error}}
            <div class="small text-warning-emphasis mt-2" data-test-error>{{this.error}}</div>
          {{/if}}
        </div>
      </div>
    {{/if}}
  </template>
}

function added(n: number) {
  return n === 1 ? '1 submission added' : `${n} submissions added`;
}
