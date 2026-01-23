import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

interface Signature {
  Args: {
    validity: components['schemas']['Validation']['validity'];
  };
}

export default <template>
  {{#if @validity}}
    <span class="badge {{colorClass @validity}} text-capitalize">{{@validity}}</span>
  {{else}}
    -
  {{/if}}
</template> satisfies TOC<Signature>;

function colorClass(validity: Exclude<Signature['Args']['validity'], null>): string {
  switch (validity) {
    case 'valid':
      return 'text-bg-success';
    case 'invalid':
      return 'text-bg-danger';
    default:
      throw new Error(validity satisfies never);
  }
}
