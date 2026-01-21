import type { TOC } from '@ember/component/template-only';

interface Signature {
  Args: {
    result?: 'success' | 'failure';
  };
}

export default <template>
  {{#if @result}}
    <span class="badge {{colorClass @result}} text-capitalize">{{@result}}</span>
  {{else}}
    -
  {{/if}}
</template> satisfies TOC<Signature>;

function colorClass(result: Exclude<Signature['Args']['result'], undefined>): string {
  switch (result) {
    case 'success':
      return 'text-bg-success';
    case 'failure':
      return 'text-bg-danger';
    default:
      throw new Error(result satisfies never);
  }
}
