import { on } from '@ember/modifier';
import { uniqueId } from '@ember/helper';

import type { TOC } from '@ember/component/template-only';

const Checkbox = <template>
  {{#let (uniqueId) as |id|}}
    <input
      type="checkbox"
      value={{@value}}
      checked={{@isSelected @value}}
      id={{id}}
      class="form-check-input"
      {{on "change" @onChange}}
    />
    <label for={{id}} class="form-check-label">{{yield}}</label>
  {{/let}}
</template> satisfies TOC<{
  Args: {
    value: string;
    onChange: (e: Event) => void;
    isSelected: (value: string) => boolean;
  };

  Blocks: {
    default: [];
  };
}>;

export default Checkbox;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'checkbox-group/checkbox': typeof Checkbox;
  }
}
