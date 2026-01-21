import type { TOC } from '@ember/component/template-only';

interface Signature {
  Args: {
    validity?: 'valid' | 'invalid' | 'error';
  };
}

export default <template>
  {{#if @validity}}
    <span class="badge {{colorClass @validity}} text-capitalize">{{@validity}}</span>
  {{else}}
    -
  {{/if}}
</template> satisfies TOC<Signature>;

function colorClass(validity: Exclude<Signature['Args']['validity'], undefined>): string {
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
