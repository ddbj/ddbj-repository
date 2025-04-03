import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { uniqueId } from '@ember/helper';

import { eq, not } from 'ember-truth-helpers';

import type Obj from 'repository/models/obj';
import type Source from 'repository/models/source';

interface Signature {
  obj: Obj;
  source: Source;
}

export default class SourceFieldComponent extends Component<Signature> {
  @action
  setFile(e: Event) {
    const { source } = this.args;

    source.file = (e.target as HTMLInputElement).files![0];
  }

  @action
  setPath(e: Event) {
    const { source } = this.args;

    source.path = (e.target as HTMLInputElement).value;
  }

  @action
  setDestination(e: Event) {
    const { source } = this.args;

    source.destination = (e.target as HTMLInputElement).value;
  }

  <template>
    <li class="list-group-item">
      <div class="mb-3">
        {{#let (uniqueId) as |id|}}
          {{#if (eq @obj.sourceType "file")}}
            <label for={{id}} class="form-label">
              File

              {{#if @source.required}}
                <span class="text-danger">*</span>
              {{/if}}
            </label>

            <input
              type="file"
              id={{id}}
              class="form-control"
              required={{@source.required}}
              {{on "change" this.setFile}}
            />
          {{else if (eq @obj.sourceType "path")}}
            <label for={{id}} class="form-label">
              Path

              {{#if @source.required}}
                <span class="text-danger">*</span>
              {{/if}}
            </label>

            <input
              type="text"
              value={{@source.path}}
              id={{id}}
              class="form-control"
              required={{@source.required}}
              {{on "change" this.setPath}}
            />
          {{/if}}
        {{/let}}
      </div>

      <div class="mb-3">
        {{#let (uniqueId) as |id|}}
          <label for={{id}} class="form-label">
            Destination
          </label>

          <input
            type="text"
            value={{@source.destination}}
            id={{id}}
            class="form-control"
            {{on "change" this.setDestination}}
          />
        {{/let}}
      </div>

      {{#if @obj.schema.multiple}}
        <div class="text-end mb-3">
          <button
            type="button"
            disabled={{not @obj.canRemoveSource}}
            class="btn btn-outline-danger"
            {{on "click" (fn @obj.removeSource @source)}}
          >Remove</button>
        </div>
      {{/if}}
    </li>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    SourceField: typeof SourceFieldComponent;
  }
}
