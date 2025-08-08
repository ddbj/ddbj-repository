import Component from '@glimmer/component';
import { action } from '@ember/object';

import { pageTitle } from 'ember-page-title';

import ValidationsSearchForm from 'repository/components/validations-search-form';
import ValidationsTable from 'repository/components/validations-table';

import type Controller from 'repository/controllers/admin/validations/index';
import type { Model } from 'repository/routes/validations-index-base';
import type { Query } from 'repository/components/validations-search-form';

interface Signature {
  Args: {
    model: Model;
    controller: Controller;
  };
}

export default class extends Component<Signature> {
  @action
  applyQuery(query: Query) {
    Object.assign(this.args.controller, query, { page: 1 });
  }

  <template>
    {{pageTitle "Validations"}}

    <ValidationsSearchForm @showUser={{true}} @onChange={{this.applyQuery}} class="bg-light p-3 border rounded" />

    <ValidationsTable
      @showUser={{true}}
      @validations={{@model.validations}}
      @page={{@controller.page}}
      @totalPages={{@model.totalPages}}
      @indexRoute="admin.validations"
      @showRoute="admin.validations.validation"
    />
  </template>
}
