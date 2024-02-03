import templateOnlyComponent from '@ember/component/template-only';

export interface Signature {
  Args: {
    value: string;
    onChange: (e: Event) => void;
    isSelected: (value: string) => boolean;
  };

  Blocks: {
    default: [];
  };
}

const CheckboxComponent = templateOnlyComponent<Signature>();

export default CheckboxComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'checkbox-group/checkbox': typeof CheckboxComponent;
  }
}
