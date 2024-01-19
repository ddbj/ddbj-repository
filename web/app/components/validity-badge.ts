import Component from '@glimmer/component';

import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    validity: Validation['validity'];
  };
}

export default class ValidityBadgeComponent extends Component<Signature> {
  get colorClass() {
    const { validity } = this.args;

    switch (validity) {
      case 'valid':
        return 'text-bg-success';
      case 'invalid':
        return 'text-bg-danger';
      case 'error':
        return 'text-bg-warning';
      case null:
        return undefined;
      default:
        throw new Error(validity satisfies never);
    }
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ValidityBadge: typeof ValidityBadgeComponent;
  }
}
