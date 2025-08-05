import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { concat, hash } from '@ember/helper';
import { getOwner } from '@ember/owner';

import { pageTitle } from 'ember-page-title';

import ValidationDetail from 'repository/components/validation-detail';

import type ValidationsIndexController from 'repository/controllers/validations/index';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    model: Validation;
  };
}

export default class extends Component<Signature> {
  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:validations.index') as ValidationsIndexController;

    return controller?.pageBefore;
  }

  <template>
    {{pageTitle (concat "Validation #" @model.id)}}

    <div class="mb-3">
      <LinkTo @route="validations.index" @query={{hash page=this.indexPage}}>&laquo; Back to index</LinkTo>
    </div>

    <ValidationDetail @validation={{@model}} />
  </template>
}
