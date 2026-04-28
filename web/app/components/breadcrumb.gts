import { LinkTo } from '@ember/routing';
import { array } from '@ember/helper';

import { or } from 'ember-truth-helpers';

import type { TOC } from '@ember/component/template-only';

export interface BreadcrumbItem {
  label: string;
  route?: string;
  models?: unknown[];
}

interface Signature {
  Args: {
    items: BreadcrumbItem[];
  };
}

const Breadcrumb = <template>
  <nav aria-label="breadcrumb">
    <ol class="breadcrumb">
      {{#each @items as |item|}}
        {{#if item.route}}
          <li class="breadcrumb-item">
            <LinkTo @route={{item.route}} @models={{or item.models (array)}}>{{item.label}}</LinkTo>
          </li>
        {{else}}
          <li class="breadcrumb-item active" aria-current="page">{{item.label}}</li>
        {{/if}}
      {{/each}}
    </ol>
  </nav>
</template> satisfies TOC<Signature>;

export default Breadcrumb;
