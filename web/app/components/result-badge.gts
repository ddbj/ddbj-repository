import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Result = components['schemas']['Submission']['result'];

interface Signature {
  Args: {
    result: Result;
  };
}

const ResultBadgeComponent: TOC<Signature> = <template>
  {{#if @result}}
    <span class='badge {{colorClass @result}} text-capitalize'>{{@result}}</span>
  {{else}}
    -
  {{/if}}
</template>;

export default ResultBadgeComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ResultBadge: typeof ResultBadgeComponent;
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
