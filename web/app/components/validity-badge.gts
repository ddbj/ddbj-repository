import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

interface Signature {
  Args: {
    validity: Exclude<components['schemas']['Validation']['validity'], null>;
  };
}

export default <template>
  <span class="badge {{colorClass @validity}} text-capitalize">{{@validity}}</span>
</template> satisfies TOC<Signature>;

function colorClass(validity: Signature['Args']['validity']): string {
  switch (validity) {
    case 'valid':
      return 'text-bg-success';
    case 'invalid':
      return 'text-bg-danger';
    default:
      throw new Error(validity satisfies never);
  }
}
