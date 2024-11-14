import Component from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { uniqueId } from '@ember/-internals/glimmer';

import { eq } from 'ember-truth-helpers';

import CheckboxGroup from 'ddbj-repository/components/checkbox-group';

import type { Task } from 'ember-concurrency';

interface Args {
  dbs: string[];
  selectedDBs: string[];
  onSelectedDBsChange: (selected: string[]) => void;
  created?: string;
  onCreatedChange: (created?: string) => void;
  progresses: string[];
  selectedProgresses: string[];
  onSelectedProgressesChange: (selected: string[]) => void;
  validities: string[];
  selectedValidities: string[];
  onSelectedValiditiesChange: (selected: string[]) => void;
  submitted?: boolean;
  onSubmittedChange: (submitted?: boolean) => void;
}

interface ArgsForUser extends Args {
  showUser?: false;
}

interface ArgsForAdmin extends Args {
  showUser: true;
  uid?: string;
  onUIDChange: Task<void, [Event]>;
}

interface Signature {
  Element: HTMLDListElement;
  Args: ArgsForUser | ArgsForAdmin;
}

export default class ValidationsSearchFormComponent extends Component<Signature> {
  createdOptions = [
    { label: 'All', value: undefined },
    { label: 'Within 1 day', value: 'within_one_day' },
    { label: 'Within 1 week', value: 'within_one_week' },
    { label: 'Within 1 month', value: 'within_one_month' },
    { label: 'Within 1 year', value: 'within_one_year' },
  ] as const;

  progressOptions = [
    { label: 'Waiting', value: 'waiting' },
    { label: 'Running', value: 'running' },
    { label: 'Finished', value: 'finished' },
    { label: 'Canceled', value: 'canceled' },
  ] as const;

  validityOptions = [
    { label: 'Valid', value: 'valid' },
    { label: 'Invalid', value: 'invalid' },
    { label: 'Error', value: 'error' },
    { label: '-', value: 'null' },
  ] as const;

  submittedOptions = [
    { label: 'All', value: undefined },
    { label: 'Submitted', value: true },
    { label: 'Not submitted', value: false },
  ] as const;

  <template>
    <dl class='horizontal align-items-center' ...attributes>
      {{#if @showUser}}
        {{#let (uniqueId) as |id|}}
          <dt>
            <label for={{id}}>User</label>
          </dt>

          <dd class='mb-0 d-flex flex-wrap gap-3 align-items-center'>
            <input
              type='text'
              value={{@uid}}
              id={{id}}
              class='form-control'
              placeholder='alice,bob'
              {{on 'input' @onUIDChange.perform}}
            />
          </dd>
        {{/let}}
      {{/if}}

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

      <dt>Created</dt>

      <dd class='mb-0 d-flex flex-wrap gap-3 align-items-center'>
        {{#each this.createdOptions as |opt|}}
          <div class='form-check'>
            {{#let (uniqueId) as |id|}}
              <input
                type='radio'
                name='created'
                checked={{eq @created opt.value}}
                id={{id}}
                class='form-check-input'
                {{on 'change' (fn @onCreatedChange opt.value)}}
              />
              <label for={{id}} class='form-check-label'>{{opt.label}}</label>
            {{/let}}
          </div>
        {{/each}}
      </dd>

      <dt>Progress</dt>

      <dd class='mb-0 d-flex flex-wrap gap-3 align-items-center'>
        <CheckboxGroup
          @values={{@progresses}}
          @selected={{@selectedProgresses}}
          @onChange={{@onSelectedProgressesChange}}
          as |group|
        >
          {{#each this.progressOptions as |opt|}}
            <div class='form-check'>
              <group.checkbox @value={{opt.value}}>
                {{opt.label}}
              </group.checkbox>
            </div>
          {{/each}}
        </CheckboxGroup>
      </dd>

      <dt>Validity</dt>

      <dd class='mb-0 d-flex flex-wrap gap-3 align-items-center'>
        <CheckboxGroup
          @values={{@validities}}
          @selected={{@selectedValidities}}
          @onChange={{@onSelectedValiditiesChange}}
          as |group|
        >
          {{#each this.validityOptions as |opt|}}
            <div class='form-check'>
              <group.checkbox @value={{opt.value}}>
                {{opt.label}}
              </group.checkbox>
            </div>
          {{/each}}
        </CheckboxGroup>
      </dd>

      <dt>Submission</dt>

      <dd class='mb-0 d-flex flex-wrap gap-3 align-items-center'>
        {{#each this.submittedOptions as |opt|}}
          <div class='form-check'>
            {{#let (uniqueId) as |id|}}
              <input
                type='radio'
                name='submitted'
                checked={{eq @submitted opt.value}}
                id={{id}}
                class='form-check-input'
                {{on 'change' (fn @onSubmittedChange opt.value)}}
              />
              <label for={{id}} class='form-check-label'>{{opt.label}}</label>
            {{/let}}
          </div>
        {{/each}}
      </dd>
    </dl>
  </template>
}

export type Created = ValidationsSearchFormComponent['createdOptions'][number]['value'];

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ValidationsSearchForm: typeof ValidationsSearchFormComponent;
  }
}
