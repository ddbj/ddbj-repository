import { array, hash } from '@ember/helper';
import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';
import RecordSlice from 'repository/components/record-slice';
import dbLabel from 'repository/helpers/db-label';

import type AccessionRoute from 'repository/routes/review/accession';
import type { TOC } from '@ember/component/template-only';

type Model = Awaited<ReturnType<AccessionRoute['model']>>;

// What one shared accession says. The submitter's screen without the
// parts a reviewer has no business with: no status, no owner, no
// conversation, and nothing to download.
export default <template>
  {{pageTitle @model.accession}}

  <Breadcrumb
    @items={{array
      (hash label=@model.setName route="review" models=(array @model.token))
      (hash label=@model.accession)
    }}
  />

  <div class="d-flex align-items-baseline gap-2 flex-wrap mb-1">
    <h1 class="display-6 mb-0 font-monospace">{{@model.accession}}</h1>
    <span class="badge text-bg-light border">{{dbLabel @model.db}}</span>
  </div>

  {{#if @model.name}}
    <p class="text-body-secondary mb-4">{{@model.name}}</p>
  {{/if}}

  {{#if @model.details}}
    <dl class="dl horizontal small mb-4" data-test-record-details>
      {{#each @model.details as |detail|}}
        <dt class="fw-normal text-body-secondary">{{detail.label}}</dt>
        <dd>{{detail.value}}</dd>
      {{/each}}
    </dl>
  {{/if}}

  <RecordSlice @record={{@model.record}} />
</template> satisfies TOC<{
  Args: {
    model: Model;
  };
}>;
