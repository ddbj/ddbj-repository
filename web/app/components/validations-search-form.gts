import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';

import { eq } from 'ember-truth-helpers';
import { restartableTask, timeout } from 'ember-concurrency';

import CheckboxGroup from 'repository/components/checkbox-group';
import arrayToQueryValue from 'repository/utils/array-to-query-value';

import {
  dbs,
  createdOptions,
  progressOptions,
  progresses,
  submittedOptions,
  validityOptions,
  validities,
} from 'repository/models/criteria';

import type { Created, Progress, Validity, Submitted } from 'repository/models/criteria';

export interface Query {
  uid?: string;
  db?: string;
  created?: string;
  progress?: string;
  validity?: string;
  submitted?: boolean;
}

interface Signature {
  Element: HTMLDListElement;

  Args: {
    showUser?: boolean;
    onChange: (query: Query) => void;
  };
}

export default class ValidationsSearchForm extends Component<Signature> {
  @tracked uid?: string;
  @tracked selectedDBs: string[] = dbs;
  @tracked created: Created;
  @tracked selectedProgresses: Progress[] = progresses;
  @tracked selectedValidities: Validity[] = validities;
  @tracked submitted: Submitted;

  get query() {
    return {
      uid: this.uid,
      db: arrayToQueryValue(this.selectedDBs, dbs),
      created: this.created,
      progress: arrayToQueryValue(this.selectedProgresses, progresses),
      validity: arrayToQueryValue(this.selectedValidities, validities),
      submitted: this.submitted,
    } satisfies Query;
  }

  onUIDChange = restartableTask(async (e: Event) => {
    const value = (e.target as HTMLInputElement).value;

    await timeout(250);

    this.uid = value === '' ? undefined : value;

    this.args.onChange(this.query);
  });

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

  @action
  onSelectedProgressesChange(selectedProgresses: Progress[]) {
    this.selectedProgresses = selectedProgresses;

    this.args.onChange(this.query);
  }

  @action
  onSelectedValiditiesChange(selectedValidities: Validity[]) {
    this.selectedValidities = selectedValidities;

    this.args.onChange(this.query);
  }

  @action
  onSubmittedChange(submitted: Submitted) {
    this.submitted = submitted;

    this.args.onChange(this.query);
  }

  <template>
    <dl class="horizontal align-items-center" ...attributes>
      {{#if @showUser}}
        {{#let (uniqueId) as |id|}}
          <dt>
            <label for={{id}}>User</label>
          </dt>

          <dd class="mb-0 d-flex flex-wrap gap-3 align-items-center">
            <input
              type="text"
              value={{this.uid}}
              id={{id}}
              class="form-control"
              placeholder="alice,bob"
              {{on "input" this.onUIDChange.perform}}
            />
          </dd>
        {{/let}}
      {{/if}}

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

      <dt>Progress</dt>

      <dd class="mb-0 d-flex flex-wrap gap-3 align-items-center">
        <CheckboxGroup
          @values={{progresses}}
          @selected={{this.selectedProgresses}}
          @onChange={{this.onSelectedProgressesChange}}
          as |group|
        >
          {{#each progressOptions as |opt|}}
            <div class="form-check">
              <group.checkbox @value={{opt.value}}>
                {{opt.label}}
              </group.checkbox>
            </div>
          {{/each}}
        </CheckboxGroup>
      </dd>

      <dt>Validity</dt>

      <dd class="mb-0 d-flex flex-wrap gap-3 align-items-center">
        <CheckboxGroup
          @values={{validities}}
          @selected={{this.selectedValidities}}
          @onChange={{this.onSelectedValiditiesChange}}
          as |group|
        >
          {{#each validityOptions as |opt|}}
            <div class="form-check">
              <group.checkbox @value={{opt.value}}>
                {{opt.label}}
              </group.checkbox>
            </div>
          {{/each}}
        </CheckboxGroup>
      </dd>

      <dt>Submission</dt>

      <dd class="mb-0 d-flex flex-wrap gap-3 align-items-center">
        {{#each submittedOptions as |opt|}}
          <div class="form-check">
            {{#let (uniqueId) as |id|}}
              <input
                type="radio"
                name="submitted"
                checked={{eq this.submitted opt.value}}
                id={{id}}
                class="form-check-input"
                {{on "change" (fn this.onSubmittedChange opt.value)}}
              />
              <label for={{id}} class="form-check-label">{{opt.label}}</label>
            {{/let}}
          </div>
        {{/each}}
      </dd>
    </dl>
  </template>
}
