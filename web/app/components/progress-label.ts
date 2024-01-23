import templateOnlyComponent from '@ember/component/template-only';

import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    progress: Validation['progress'];
  };
}

const ProgressLabelComponent = templateOnlyComponent<Signature>();

export default ProgressLabelComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ProgressLabel: typeof ProgressLabelComponent;
  }
}
