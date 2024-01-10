import Component from '@glimmer/component';

interface Signature {
  Args: {
    validity: string;
  };
}

export default class ValidityBadgeComponent extends Component<Signature> {
  get colorClass() {
    const { validity } = this.args;

    return validity === 'valid'
      ? 'text-bg-success'
      : validity === 'invalid'
        ? 'text-bg-danger'
        : validity === 'error'
          ? 'text-bg-warning'
          : 'text-bg-secondary';
  }
}
