import Component from '@glimmer/component';
import { action } from '@ember/object';

import type CheckboxComponent from 'ddbj-repository/components/checkbox-group/checkbox';
import type { WithBoundArgs } from '@glint/template';

interface Signature {
  Args: {
    values: string[];
    selected: string[];
    onChange: (values: string[]) => void;
  };

  Blocks: {
    default: [{ checkbox: WithBoundArgs<typeof CheckboxComponent, 'onChange' | 'isSelected'> }];
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
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    CheckboxGroup: typeof CheckboxGroupComponent;
  }
}
