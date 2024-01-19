import Component from '@glimmer/component';
import { action } from '@ember/object';

import type Obj from 'ddbj-repository/models/obj';
import type Source from 'ddbj-repository/models/source';

interface Signature {
  obj: Obj;
  source: Source;
}

export default class SourceFieldComponent extends Component<Signature> {
  @action
  setFile(e: Event) {
    const { source } = this.args;

    source.file = (e.target as HTMLInputElement).files![0];
  }

  @action
  setPath(e: Event) {
    const { source } = this.args;

    source.path = (e.target as HTMLInputElement).value;
  }

  @action
  setDestination(e: Event) {
    const { source } = this.args;

    source.destination = (e.target as HTMLInputElement).value;
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    SourceField: typeof SourceFieldComponent;
  }
}
