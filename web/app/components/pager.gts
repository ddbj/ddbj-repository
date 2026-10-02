import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';

// Prev/Next rather than the routed pager (Pagination): for a list that
// lives inside a component on a screen of its own, so a page of it is not a
// place the browser goes.
export default class Pager extends Component<{
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
      <nav class="d-flex flex-wrap align-items-center gap-2 mb-3" aria-label="Pages of {{@label}}">
        {{! Both ends, not only the neighbours. Such a list can be as long
        as everything somebody submitted, and stepping to page 5,000 one
        press at a time is not a way back to the end of it. }}
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
