import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { uniqueId } from '@ember/helper';

import { eq } from 'ember-truth-helpers';

import { DB_LABELS } from 'repository/helpers/db-label';
import { getText } from 'repository/utils/form-data';

interface Signature {
  Args: {
    db: string;
    user: string;
    onApply: (filters: { db: string; user: string }) => void;
  };
}

export default class AdminListFilter extends Component<Signature> {
  @action
  submit(e: Event) {
    e.preventDefault();

    const data = new FormData(e.target as HTMLFormElement);

    this.args.onApply({
      db: getText(data, 'db'),
      user: getText(data, 'user'),
    });
  }

  <template>
    <form class="row g-2 mb-3" {{on "submit" this.submit}}>
      {{#let (uniqueId) (uniqueId) as |dbId userId|}}
        <div class="col-sm-4">
          <label for={{dbId}} class="form-label visually-hidden">Database</label>

          <select name="db" id={{dbId}} class="form-select">
            <option value="" selected={{eq @db ""}}>All databases</option>

            {{#each-in DB_LABELS as |value label|}}
              <option value={{value}} selected={{eq @db value}}>{{label}}</option>
            {{/each-in}}
          </select>
        </div>

        <div class="col-sm-6">
          <label for={{userId}} class="form-label visually-hidden">User uid</label>

          <input
            type="search"
            name="user"
            id={{userId}}
            value={{@user}}
            class="form-control"
            placeholder="Filter by user uid"
          />
        </div>

        <div class="col-sm-2">
          <button type="submit" class="btn btn-primary w-100">Filter</button>
        </div>
      {{/let}}
    </form>
  </template>
}
