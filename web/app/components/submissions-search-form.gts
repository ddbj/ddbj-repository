import Component from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
// @ts-expect-error https://github.com/emberjs/ember.js/pull/20464
import { uniqueId } from '@ember/-internals/glimmer';

import { eq } from 'ember-truth-helpers';

import CheckboxGroup from 'ddbj-repository/components/checkbox-group';

import type { Task } from 'ember-concurrency';


interface Signature {
  Element: HTMLDListElement;

  Args: {
    dbs: string[];
    selectedDBs: string[];
    onSelectedDBsChange: (selected: string[]) => void;
    onSubmittedChange: (submitted?: boolean) => void;
  }
}

export default class SubmissionsSearchFormComponent extends Component<Signature> {
  <template>
    <dl class='horizontal align-items-center' ...attributes>
      <dt>DB</dt>

      <dd class='mb-0 d-flex flex-wrap gap-3 align-items-center'>
        <CheckboxGroup @values={{@dbs}} @selected={{@selectedDBs}} @onChange={{@onSelectedDBsChange}} as |group|>
          {{#each @dbs as |db|}}
            <div class='form-check'>
              <group.checkbox @value={{db}}>
                {{db}}
              </group.checkbox>
            </div>
          {{/each}}
        </CheckboxGroup>
      </dd>
    </dl>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    SubmissionsSearchForm: typeof SubmissionsSearchFormComponent;
  }
}

