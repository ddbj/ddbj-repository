import { eq, or } from 'ember-truth-helpers';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    progress: Validation['progress'];
  };
}

const ProgressLabelComponent: TOC<Signature> = <template>
  <div class='d-flex align-items-center gap-1'>
    {{#if (or (eq @progress 'waiting') (eq @progress 'running'))}}
      <div class='spinner-border spinner-border-sm text-secondary' role='status'></div>
    {{/if}}

    <div class='text-capitalize'>{{@progress}}</div>
  </div>
</template>;

export default ProgressLabelComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ProgressLabel: typeof ProgressLabelComponent;
  }
}
