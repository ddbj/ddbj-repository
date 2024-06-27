import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Code = components['schemas']['ValidationResult']['details'][0]['code'];

interface Signature {
  Args: {
    code: Code;
  };
}

const ErrorCodeComponent: TOC<Signature> = <template>
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
</template>;

export default ErrorCodeComponent;

function url(code: Exclude<Code, null>) {
  if (/^BS_R\d{4}$/.test(code)) {
    return `https://www.ddbj.nig.ac.jp/biosample/validation-e.html#${code}`;
  } else {
    return undefined;
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ErrorCode: typeof ErrorCodeComponent;
  }
}
