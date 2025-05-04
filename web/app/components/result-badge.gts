import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Result = components['schemas']['Submission']['result'];

const ResultBadge = <template>
  {{#if @result}}
    <span class="badge {{colorClass @result}} text-capitalize">{{@result}}</span>
  {{else}}
    -
  {{/if}}
</template> satisfies TOC<{
  Args: {
    result: Result;
  };
}>;

export default ResultBadge;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ResultBadge: typeof ResultBadge;
  }
}

function colorClass(result: Exclude<Result, null>) {
  switch (result) {
    case 'success':
      return 'text-bg-success';
    case 'failure':
      return 'text-bg-danger';
    default:
      throw new Error(result satisfies never);
  }
}
