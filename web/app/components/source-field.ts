import Component from '@glimmer/component';
import { action } from '@ember/object';

import { Obj, Source } from 'ddbj-repository/components/submit-form';

type Signature = {
  obj: Obj;
  source: Source;
};

export default class SourceFieldComponent extends Component<Signature> {
  @action
  setFile(e: Event) {
    const { source } = this.args;

    source.file = (e.target as HTMLInputElement).files![0];
  }
}
