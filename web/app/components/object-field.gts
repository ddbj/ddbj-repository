import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';

import { eq } from 'ember-truth-helpers';

import SourceField from 'repository/components/source-field';

import type Obj from 'repository/models/obj';

interface Signature {
  Args: {
    obj: Obj;
  };
}

export default class ObjectField extends Component<Signature> {
  @action
  setSourceType(val: Obj['sourceType']) {
    const { obj } = this.args;

    obj.sourceType = val;
  }

  <template>
    <div class="card mb-3">
      <div class="card-header">
        {{@obj.schema.id}}
      </div>

      <div class="card-body">
        {{#let (uniqueId) as |name|}}
          <div class="form-check form-check-inline">
            {{#let (uniqueId) as |id|}}
              <input
                type="radio"
                checked={{eq @obj.sourceType "file"}}
                name={{name}}
                id={{id}}
                {{on "click" (fn this.setSourceType "file")}}
              />
              <label class="form-check-label" for={{id}}>File</label>
            {{/let}}
          </div>

          <div class="form-check form-check-inline">
            {{#let (uniqueId) as |id|}}
              <input
                type="radio"
                checked={{eq @obj.sourceType "path"}}
                name={{name}}
                id={{id}}
                {{on "click" (fn this.setSourceType "path")}}
              />
              <label class="form-check-label" for={{id}}>Path</label>
            {{/let}}
          </div>
        {{/let}}
      </div>

      <ul class="list-group list-group-flush">
        {{#each @obj.sources as |source|}}
          <SourceField @obj={{@obj}} @source={{source}} />
        {{else}}
          <li class="list-group-item py-3">No items.</li>
        {{/each}}
      </ul>

      {{#if @obj.schema.multiple}}
        <div class="card-body text-end">
          <button type="button" class="btn btn-outline-primary" {{on "click" @obj.addSource}}>Add</button>
        </div>
      {{/if}}
    </div>
  </template>
}
