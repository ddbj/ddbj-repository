import Component from '@glimmer/component';
import { action } from '@ember/object';

import type Obj from 'ddbj-repository/models/obj';

interface Signature {
  Args: {
    obj: Obj;
  };
}

export default class ObjectFieldComponent extends Component<Signature> {
  @action
  setSourceType(val: Obj['sourceType']) {
    const { obj } = this.args;

    obj.sourceType = val;
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ObjectField: typeof ObjectFieldComponent;
  }
}
