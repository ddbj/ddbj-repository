import CheckboxGroup from 'ddbj-repository/components/checkbox-group';

import type { TOC } from '@ember/component/template-only';

interface Signature {
  Element: HTMLDListElement;

  Args: {
    dbs: string[];
    selectedDBs: string[];
    onSelectedDBsChange: (selected: string[]) => void;
  };
}

const SubmissionsSearchFormComponent: TOC<Signature> = <template>
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
</template>;

export default SubmissionsSearchFormComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    SubmissionsSearchForm: typeof SubmissionsSearchFormComponent;
  }
}
