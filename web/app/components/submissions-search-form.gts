import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

import { eq } from 'ember-truth-helpers';

import CheckboxGroup from 'repository/components/checkbox-group';
import arrayToQueryValue from 'repository/utils/array-to-query-value';
import { dbs, createdOptions } from 'repository/models/criteria';

import type { Created } from 'repository/models/criteria';

export interface Query {
  db?: string;
  created?: string;
}

interface Signature {
  Element: HTMLDListElement;

  Args: {
    onChange: (query: Query) => void;
  };
}

export default class SubmissionsSearchForm extends Component<Signature> {
  @tracked selectedDBs: string[] = dbs;
  @tracked created?: Created;

  get query() {
    return {
      db: arrayToQueryValue(this.selectedDBs, dbs),
      created: this.created,
    } satisfies Query;
  }

  @action
  onSelectedDBsChange(selectedDBs: string[]) {
    this.selectedDBs = selectedDBs;

    this.args.onChange(this.query);
  }

  @action
  onCreatedChange(created: Created) {
    this.created = created;

    this.args.onChange(this.query);
  }

  <template>
    <dl class="horizontal align-items-center" ...attributes>
      <dt>DB</dt>

      <dd class="mb-0 d-flex flex-wrap gap-3 align-items-center">
        <CheckboxGroup @values={{dbs}} @selected={{this.selectedDBs}} @onChange={{this.onSelectedDBsChange}} as |group|>
          {{#each dbs as |db|}}
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
        {{#each createdOptions as |opt|}}
          <div class="form-check">
            {{#let (uniqueId) as |id|}}
              <input
                type="radio"
                name="created"
                checked={{eq this.created opt.value}}
                id={{id}}
                class="form-check-input"
                {{on "change" (fn this.onCreatedChange opt.value)}}
              />
              <label for={{id}} class="form-check-label">{{opt.label}}</label>
            {{/let}}
          </div>
        {{/each}}
      </dd>
    </dl>
  </template>
}
