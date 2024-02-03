import Component from '@glimmer/component';
import { action } from '@ember/object';

interface Signature {
  Args: {
    values: string[];
    selected: string[];
    onChange: (values: string[]) => void;
  };

  Blocks: {
    default: [CheckboxesComponent];
  };
}

export default class CheckboxesComponent extends Component<Signature> {
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
    Checkboxes: typeof CheckboxesComponent;
  }
}
