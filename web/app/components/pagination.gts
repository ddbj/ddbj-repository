import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { hash } from '@ember/helper';

import { eq } from 'ember-truth-helpers';

interface Signature {
  Element: HTMLElement;

  Args: {
    route: string;
    current: number;
    last: number;
  };
}

export default class PaginationComponent extends Component<Signature> {
  get pages() {
    const { last } = this.args;

    return [...Array(last)].map((_, i) => i + 1);
  }

  get prev() {
    const { current } = this.args;

    return current === 1 ? undefined : current - 1;
  }

  get next() {
    const { current, last } = this.args;

    return current === last ? undefined : current + 1;
  }

  <template>
    <nav class='d-flex justify-content-center' ...attributes>
      <ul class='pagination'>
        <li class='page-item {{unless this.prev "disabled" ""}}' data-test-prev>
          {{#if this.prev}}
            <LinkTo @route={{@route}} @query={{hash page=this.prev}} class='page-link' aria-label='Previous'>
              <span aria-hidden='true'>&laquo;</span>
            </LinkTo>
          {{else}}
            <a href='#' class='page-link' aria-label='Previous'>
              <span aria-hidden='true'>&laquo;</span>
            </a>
          {{/if}}
        </li>

        {{#each this.pages as |page|}}
          <li class='page-item {{if (eq page @current) "active" ""}}' data-test-page={{page}}>
            <LinkTo @route={{@route}} @query={{hash page=page}} class='page-link'>
              {{page}}
            </LinkTo>
          </li>
        {{/each}}

        <li class='page-item {{unless this.next "disabled" ""}}' data-test-next>
          {{#if this.next}}
            <LinkTo @route={{@route}} @query={{hash page=this.next}} class='page-link' aria-label='Previous'>
              <span aria-hidden='true'>&raquo;</span>
            </LinkTo>
          {{else}}
            <a href='#' class='page-link' aria-label='Next'>
              <span aria-hidden='true'>&raquo;</span>
            </a>
          {{/if}}
        </li>
      </ul>
    </nav>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    Pagination: typeof PaginationComponent;
  }
}
