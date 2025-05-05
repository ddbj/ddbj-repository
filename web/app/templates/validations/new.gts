import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';

import { eq } from 'ember-truth-helpers';
import { pageTitle } from 'ember-page-title';

import DB from 'repository/models/db';
import ENV from 'repository/config/environment';
import NewValidationForm from 'repository/components/new-validation-form';
import ValidationsNewController from 'repository/controllers/validations/new';

interface Signature {
  Args: {
    controller: ValidationsNewController;
  };
}

const dbs = ENV.dbs.map((db) => new DB(db));

export default class extends Component<Signature> {
  get selectedDb() {
    return dbs.find((db) => db.schema.id === this.args.controller.db)!;
  }

  @action
  selectDb(db: DB) {
    this.args.controller.db = db.schema.id;
  }

  <template>
    {{pageTitle "New Validation"}}

    <h1 class="display-6 mb-4">New Validation</h1>

    <ul class="nav nav-tabs mb-3" role="tablist">
      {{#each dbs as |db|}}
        <li class="nav-item" role="presentation">
          <button
            type="button"
            class="nav-link {{if (eq db this.selectedDb) 'active' ''}}"
            aria-current={{if (eq db this.selectedDb) "page" ""}}
            {{on "click" (fn this.selectDb db)}}
          >
            {{db.schema.id}}
          </button>
        </li>
      {{/each}}
    </ul>

    <NewValidationForm @db={{this.selectedDb}} />
  </template>
}
