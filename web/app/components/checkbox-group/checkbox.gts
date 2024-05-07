import { on } from '@ember/modifier';
// @ts-expect-error https://github.com/emberjs/ember.js/pull/20464
import { uniqueId } from '@ember/-internals/glimmer';

import type { TOC } from '@ember/component/template-only';

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

const CheckboxComponent: TOC<Signature> = <template>
  {{#let (uniqueId) as |id|}}
    <input
      type='checkbox'
      value={{@value}}
      checked={{@isSelected @value}}
      id={{id}}
      class='form-check-input'
      {{on 'change' @onChange}}
    />
    <label for={{id}} class='form-check-label'>{{yield}}</label>
  {{/let}}
</template>;

export default CheckboxComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'checkbox-group/checkbox': typeof CheckboxComponent;
  }
}
