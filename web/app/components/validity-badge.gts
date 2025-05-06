import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Validity = components['schemas']['Validation']['validity'];

export default <template>
  {{#if @validity}}
    <span class="badge {{colorClass @validity}} text-capitalize">{{@validity}}</span>
  {{else}}
    -
  {{/if}}
</template> satisfies TOC<{
  Args: {
    validity: Validity;
  };
}>;

function colorClass(validity: Exclude<Validity, null>) {
  switch (validity) {
    case 'valid':
      return 'text-bg-success';
    case 'invalid':
      return 'text-bg-danger';
    case 'error':
      return 'text-bg-warning';
    default:
      throw new Error(validity satisfies never);
  }
}
