import style from 'ember-style-modifier';

import type { TOC } from '@ember/component/template-only';

interface Signature {
  Element: HTMLTableElement;

  Args: {
    items: unknown[];
  };

  Blocks: {
    default: [];
  };
}

export default <template>
  {{#if @items}}
    <table class="table border" ...attributes>
      {{yield}}
    </table>
  {{else}}
    <div class="text-center text-muted border rounded py-5" {{style --bs-border-style="dashed"}}>
      There are no items.
    </div>
  {{/if}}
</template> satisfies TOC<Signature>;
