import type { TOC } from '@ember/component/template-only';

interface Signature {
  Args: {
    code?: string;
  };
}

export default <template>
  {{#if @code}}
    {{#let (url @code) as |url|}}
      {{#if url}}
        <a href={{url}}>{{@code}}</a>
      {{else}}
        {{@code}}
      {{/if}}
    {{/let}}
  {{else}}
    -
  {{/if}}
</template> satisfies TOC<Signature>;

function url(code: string): string | null {
  if (/^BS_R\d{4}$/.test(code)) {
    return `https://www.ddbj.nig.ac.jp/biosample/validation-e.html#${code}`;
  } else {
    return null;
  }
}
