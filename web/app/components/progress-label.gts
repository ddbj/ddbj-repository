import { eq, or } from 'ember-truth-helpers';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export default <template>
  <div class="d-flex align-items-center gap-1">
    {{#if (or (eq @progress "waiting") (eq @progress "running"))}}
      <div class="spinner-border spinner-border-sm text-secondary" role="status"></div>
    {{/if}}

    <div class="text-capitalize">{{@progress}}</div>
  </div>
</template> satisfies TOC<{
  Args: {
    progress: Validation['progress'];
  };
}>;
