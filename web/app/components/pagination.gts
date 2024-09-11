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

const window = 5;

export default class PaginationComponent extends Component<Signature> {
  get pages() {
    const { current, last } = this.args;

    const start = Math.max(1, current - window);
    const end = Math.min(last, current + window);

    return Array.from({ length: end - start + 1 }, (_, i) => start + i);
  }

  get prev() {
    const { current } = this.args;

    return current === 1 ? undefined : current - 1;
  }

  get next() {
    const { current, last } = this.args;

    return current === last ? undefined : current + 1;
  }

  get hasPrevGap() {
    const { current } = this.args;

    return current > window + 1;
  }

  get hasNextGap() {
    const { current, last } = this.args;

    return current < last - window;
  }

  <template>
    <nav class='d-flex justify-content-center' ...attributes>
      <ul class='pagination'>
        <li class='page-item {{unless this.prev "disabled" ""}}' data-test-start>
          {{#if this.prev}}
            <LinkTo @route={{@route}} @query={{hash page=1}} class='page-link' aria-label='Start'>
              <span aria-hidden='true'>«</span>
            </LinkTo>
          {{else}}
            <a href='#' class='page-link' aria-label='Previous'>
              <span aria-hidden='true'>«</span>
            </a>
          {{/if}}
        </li>

        <li class='page-item {{unless this.prev "disabled" ""}}' data-test-prev>
          {{#if this.prev}}
            <LinkTo @route={{@route}} @query={{hash page=this.prev}} class='page-link' aria-label='Previous'>
              <span aria-hidden='true'>‹</span>
            </LinkTo>
          {{else}}
            <a href='#' class='page-link' aria-label='Previous'>
              <span aria-hidden='true'>‹</span>
            </a>
          {{/if}}
        </li>

        {{#if this.hasPrevGap}}
          <li class='page-item disabled'>
            <a href='#' class='page-link'>...</a>
          </li>
        {{/if}}

        {{#each this.pages as |page|}}
          <li class='page-item {{if (eq page @current) "active" ""}}' data-test-page={{page}}>
            <LinkTo @route={{@route}} @query={{hash page=page}} class='page-link'>
              {{page}}
            </LinkTo>
          </li>
        {{/each}}

        {{#if this.hasNextGap}}
          <li class='page-item disabled'>
            <a href='#' class='page-link'>...</a>
          </li>
        {{/if}}

        <li class='page-item {{unless this.next "disabled" ""}}' data-test-next>
          {{#if this.next}}
            <LinkTo @route={{@route}} @query={{hash page=this.next}} class='page-link' aria-label='Next'>
              <span aria-hidden='true'>›</span>
            </LinkTo>
          {{else}}
            <a href='#' class='page-link' aria-label='Next'>
              <span aria-hidden='true'>›</span>
            </a>
          {{/if}}
        </li>

        <li class='page-item {{unless this.next "disabled" ""}}' data-test-last>
          {{#if this.next}}
            <LinkTo @route={{@route}} @query={{hash page=@last}} class='page-link' aria-label='Last'>
              <span aria-hidden='true'>»</span>
            </LinkTo>
          {{else}}
            <a href='#' class='page-link' aria-label='Next'>
              <span aria-hidden='true'>»</span>
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
