import Component from '@glimmer/component';
import { action } from '@ember/object';
import { hash } from '@ember/helper';
import { on } from '@ember/modifier';

import Checkbox from 'repository/components/checkbox-group/checkbox';

import type { WithBoundArgs } from '@glint/template';

interface Signature {
  Args: {
    values: string[];
    selected: string[];
    onChange: (values: string[]) => void;
  };

  Blocks: {
    default: [{ checkbox: WithBoundArgs<typeof Checkbox, 'onChange' | 'isSelected'> }];
  };
}

export default class CheckboxGroupComponent extends Component<Signature> {
  isSelected = (val: string) => this.args.selected.includes(val);

  @action
  onChange(e: Event) {
    const { checked, value } = e.target as HTMLInputElement;
    const { selected, onChange } = this.args;

    const newSelected = checked ? [...selected, value] : selected.filter((val) => val !== value);

    onChange(newSelected);
  }

  @action checkAll() {
    const { onChange, values } = this.args;

    onChange(values);
  }

  @action clear() {
    const { onChange } = this.args;

    onChange([]);
  }

  <template>
    {{yield (hash checkbox=(component Checkbox onChange=this.onChange isSelected=this.isSelected))}}

    <div class="btn-group btn-group-sm">
      <button type="button" class="btn btn-link" {{on "click" this.checkAll}}>Check all</button>
      <button type="button" class="btn btn-link" {{on "click" this.clear}}>Clear</button>
    </div>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    CheckboxGroup: typeof CheckboxGroupComponent;
  }
}
