import Component from '@glimmer/component';

import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    results: Validation['results'];
  };
}

export default class DetailsCountComponent extends Component<Signature> {
  get count() {
    const { results } = this.args;

    return results.map(({ details }) => details).filter(Boolean).length;
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    DetailsCount: typeof DetailsCountComponent;
  }
}
