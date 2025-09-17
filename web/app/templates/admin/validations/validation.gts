import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { concat, hash } from '@ember/helper';
import { getOwner } from '@ember/owner';

import { pageTitle } from 'ember-page-title';

import ValidationDetail from 'repository/components/validation-detail';

import type AdminValidationsIndexController from 'repository/controllers/admin/validations/index';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['ValidationWithSubmission'];

interface Signature {
  Args: {
    model: Validation;
  };
}

export default class extends Component<Signature> {
  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:admin.validations.index') as AdminValidationsIndexController;

    return controller?.pageBefore;
  }

  <template>
    {{pageTitle (concat "Validation #" @model.id)}}

    <div class="mb-3">
      <LinkTo @route="admin.validations.index" @query={{hash page=this.indexPage}}>&laquo; Back to index</LinkTo>
    </div>

    <ValidationDetail @validation={{@model}} @showUser={{true}} />
  </template>
}
