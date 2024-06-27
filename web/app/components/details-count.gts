import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Results = components['schemas']['Validation']['results'];

interface Signature {
  Args: {
    results: Results;
  };
}

const DetailsCountComponent: TOC<Signature> = <template>
  {{#let (detailsCount @results) as |count|}}
    {{#if count}}
      <span class='badge bg-secondary'>{{count}}</span>
    {{/if}}
  {{/let}}
</template>;

export default DetailsCountComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    DetailsCount: typeof DetailsCountComponent;
  }
}

function detailsCount(results: Results) {
  return results.reduce((acc, { details }) => acc + details.length, 0);
}
