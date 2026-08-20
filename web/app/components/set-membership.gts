import Component from '@glimmer/component';
import { action } from '@ember/object';
import { concat, fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { uniqueId } from '@ember/helper';
import { LinkTo } from '@ember/routing';

import { errorMessage } from 'repository/utils/error-message';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';
import type { components, paths } from 'schema/openapi';

type Sets = paths['/sets']['get']['responses']['200']['content']['application/json'];
type Membership = components['schemas']['SubmissionRequest']['sets'][number];

interface Signature {
  Args: {
    requestId: number;
    sets: Membership[];
  };
}

// Putting your own submission into a set, and taking it back out. It
// lives on the submission's own page rather than on the set's because
// that is where the decision belongs: a set's other members can read
// what is in it, and only the owner of a submission says whether theirs
// is.
export default class SetMembership extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  @tracked mine: Sets = [];
  @tracked selected = '';
  @tracked busy = false;
  @tracked error: string | null = null;

  // Separate from `mine.length`, so a failed load does not tell somebody
  // who is in six sets to go and create one.
  @tracked loaded = false;

  constructor(owner: unknown, args: Signature['Args']) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);

    // Swallowed on purpose: this is a panel offering a convenience, and
    // a modal over the submission page because the set list could not
    // be fetched would be worse than the panel saying nothing. `loaded`
    // stays false, so it does not claim the reader has no sets either.
    void this.load().catch(() => {});
  }

  async load() {
    const { content } = await this.requestManager.request<Sets>({ url: '/sets' });

    this.mine = content;
    this.loaded = true;
  }

  // Only the ones it is not in yet. Offering a set it already belongs
  // to would be an option whose only outcome is an error.
  get available() {
    const already = new Set(this.args.sets.map((set) => set.id));

    return this.mine.filter((set) => !already.has(set.id));
  }

  get hasNoSets() {
    return this.loaded && this.mine.length === 0;
  }

  // Already in all of them. Without a branch for this the panel renders
  // the list and nothing else — no picker, no way on — which reads as
  // "a submission belongs to one set". It does not: a BioProject is a
  // hub, and the sets hanging off one are different collaborations.
  get inEverySet() {
    return this.loaded && this.mine.length > 0 && this.available.length === 0;
  }

  get addDisabled() {
    return this.busy || !this.selected;
  }

  @action
  updateSelected(e: Event) {
    this.selected = (e.target as HTMLSelectElement).value;
  }

  @action
  async add() {
    if (this.busy || !this.selected) return;

    this.busy = true;
    this.error = null;

    try {
      await this.requestManager.request({
        url: `/sets/${this.selected}/submissions`,
        method: 'POST',
        data: { submission_request_ids: [this.args.requestId] },
      });

      this.selected = '';
      this.toast.show('Added to the set.', 'success');

      await this.router.refresh();
    } catch (e) {
      this.error = errorMessage(e) ?? 'Could not add it to that set. Try again.';
    } finally {
      this.busy = false;
    }
  }

  @action
  async remove(setId: number) {
    if (this.busy) return;

    this.busy = true;
    this.error = null;

    try {
      await this.requestManager.request({
        url: `/sets/${setId}/submissions/${this.args.requestId}`,
        method: 'DELETE',
      });

      this.toast.show('Taken out of the set.', 'success');

      await this.router.refresh();
    } catch (e) {
      this.error = errorMessage(e) ?? 'Could not take it out. Try again.';
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{! No heading: this is the body of a disclosure whose summary already
    says "Sets", and saying it twice makes the reader look for the
    difference. }}
    <section data-test-sets>
      <p class="text-body-secondary small">
        A set is submissions that belong together — the ones behind a paper, a study, a piece of work. Everyone in the
        set can see this submission and how far along it is. Taking it back out is always yours to do.
      </p>

      {{#if this.error}}
        <div class="alert alert-warning" data-test-error>{{this.error}}</div>
      {{/if}}

      {{#if @sets.length}}
        <ul class="list-group mb-3">
          {{#each @sets as |set|}}
            <li class="list-group-item d-flex justify-content-between align-items-center">
              <LinkTo @route="set" @model={{set.id}}>{{set.name}}</LinkTo>

              <button
                type="button"
                class="btn btn-outline-secondary btn-sm"
                disabled={{this.busy}}
                aria-label={{concat "Take this submission out of " set.name}}
                {{on "click" (fn this.remove set.id)}}
              >
                Take out
              </button>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="small text-body-secondary">This submission is not in any set.</p>
      {{/if}}

      {{#if this.available.length}}
        <div class="row g-2 align-items-end">
          <div class="col-auto">
            {{#let (uniqueId) as |id|}}
              <label for={{id}} class="form-label">{{if @sets.length "Add to another set" "Add to a set"}}</label>

              <select id={{id}} class="form-select" {{on "change" this.updateSelected}}>
                <option value="">Choose a set…</option>

                {{#each this.available as |set|}}
                  <option value={{set.id}} selected={{eq (concat set.id) this.selected}}>{{set.name}}</option>
                {{/each}}
              </select>
            {{/let}}
          </div>

          <div class="col-auto">
            <button type="button" class="btn btn-primary" disabled={{this.addDisabled}} {{on "click" this.add}}>
              Add
            </button>
          </div>
        </div>
      {{else if this.inEverySet}}
        <p class="small text-body-secondary mb-0">
          It is in every set you are in. A submission can be in as many as it belongs in —
          <LinkTo @route="sets">make another</LinkTo>
          if it is part of something else too.
        </p>
      {{else if this.hasNoSets}}
        <p class="small text-body-secondary mb-0">
          <LinkTo @route="sets">Create a set</LinkTo>
          to keep this with the submissions it belongs with.
        </p>
      {{/if}}
    </section>
  </template>
}
