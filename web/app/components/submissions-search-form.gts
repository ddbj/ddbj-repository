import Component from '@glimmer/component';
import { fn, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';

import { eq } from 'ember-truth-helpers';

import CheckboxGroup from 'repository/components/checkbox-group';

interface Signature {
  Element: HTMLDListElement;

  Args: {
    dbs: string[];
    selectedDBs: string[];
    onSelectedDBsChange: (selected: string[]) => void;
    created?: string;
    onCreatedChange: (created?: string) => void;
  };
}

export default class SubmissionsSearchFormComponent extends Component<Signature> {
  createdOptions = [
    { label: 'All', value: undefined },
    { label: 'Within 1 day', value: 'within_one_day' },
    { label: 'Within 1 week', value: 'within_one_week' },
    { label: 'Within 1 month', value: 'within_one_month' },
    { label: 'Within 1 year', value: 'within_one_year' },
  ] as const;

  <template>
    <dl class="horizontal align-items-center" ...attributes>
      <dt>DB</dt>

      <dd class="mb-0 d-flex flex-wrap gap-3 align-items-center">
        <CheckboxGroup @values={{@dbs}} @selected={{@selectedDBs}} @onChange={{@onSelectedDBsChange}} as |group|>
          {{#each @dbs as |db|}}
            <div class="form-check">
              <group.checkbox @value={{db}}>
                {{db}}
              </group.checkbox>
            </div>
          {{/each}}
        </CheckboxGroup>
      </dd>

      <dt>Created</dt>

      <dd class="mb-0 d-flex flex-wrap gap-3 align-items-center">
        {{#each this.createdOptions as |opt|}}
          <div class="form-check">
            {{#let (uniqueId) as |id|}}
              <input
                type="radio"
                name="created"
                checked={{eq @created opt.value}}
                id={{id}}
                class="form-check-input"
                {{on "change" (fn @onCreatedChange opt.value)}}
              />
              <label for={{id}} class="form-check-label">{{opt.label}}</label>
            {{/let}}
          </div>
        {{/each}}
      </dd>
    </dl>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    SubmissionsSearchForm: typeof SubmissionsSearchFormComponent;
  }
}
