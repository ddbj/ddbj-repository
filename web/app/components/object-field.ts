import Component from '@glimmer/component';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

interface Args {
  object: {
    optional: boolean;
    multiple: boolean;
  };
}

interface Signature {
  Args: Args;
}

export default class ObjectFieldComponent extends Component<Signature> {
  @tracked source = 'file';
  @tracked instances: symbol[];

  constructor(owner: unknown, args: Args) {
    super(owner, args);

    const { object } = this.args;

    this.instances = object.multiple && object.optional ? [] : [Symbol()];
  }

  @action
  add() {
    this.instances = [...this.instances, Symbol()];
  }

  @action
  remove(instance: symbol) {
    this.instances = this.instances.filter((sym) => sym !== instance);
  }
}
