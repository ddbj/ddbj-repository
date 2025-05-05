import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Results = components['schemas']['Validation']['results'];

export default <template>
  {{#let (detailsCount @results) as |count|}}
    {{#if count}}
      <span class="badge bg-secondary">{{count}}</span>
    {{/if}}
  {{/let}}
</template> satisfies TOC<{
  Args: {
    results: Results;
  };
}>;

function detailsCount(results: Results) {
  return results.reduce((acc, { details }) => acc + details.length, 0);
}
