import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';

import ValidationsSearchForm from 'repository/components/validations-search-form';
import ValidationsTable from 'repository/components/validations-table';

import type Controller from 'repository/controllers/validations/index';
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
    <h1 class="display-6 mb-4">Validations</h1>

    <div class="mb-3">
      <LinkTo @route="validations.new" class="btn btn-primary">New Validation</LinkTo>
    </div>

    <ValidationsSearchForm @onChange={{this.applyQuery}} class="bg-light p-3 border rounded" />

    <ValidationsTable
      @validations={{@model.validations}}
      @page={{@controller.page}}
      @totalPages={{@model.totalPages}}
      @indexRoute="validations"
      @showRoute="validation"
    />
  </template>
}
