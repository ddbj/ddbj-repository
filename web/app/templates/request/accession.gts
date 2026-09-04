import { array, concat, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import RecordNode from 'repository/components/record-node';
import dbLabel from 'repository/helpers/db-label';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type AccessionRecord = components['schemas']['AccessionRecord'];

// What one accession's record says, laid out by the shape of the data.
// Nothing here names a field — a new v3 key appears the day it lands
// rather than the day somebody revises this.
export default <template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label=(concat "#" @model.requestId) route="request" models=(array @model.requestId))
      (hash label="Accessions" route="request.accessions" models=(array @model.requestId))
      (hash label=@model.record.accession)
    }}
  />

  <div class="d-flex align-items-baseline gap-2 flex-wrap mb-1">
    <h1 class="display-6 mb-0 font-monospace">{{@model.record.accession}}</h1>
    <span class="badge text-bg-light border">{{dbLabel @model.record.db}}</span>
    <span class="badge text-bg-light border text-capitalize">{{@model.record.status}}</span>
  </div>

  {{#if @model.record.name}}
    <p class="text-body-secondary mb-4">{{@model.record.name}}</p>
  {{/if}}

  {{#if @model.record.details}}
    {{! What the typed columns say about this row. Drawn whether or not
    the record can be read — on the one screen where it cannot, these are
    the only thing the page has to show. }}
    <dl class="dl horizontal small mb-4" data-test-record-details>
      {{#each @model.record.details as |detail|}}
        <dt class="fw-normal text-body-secondary">{{detail.label}}</dt>
        <dd>{{detail.value}}</dd>
      {{/each}}
    </dl>
  {{/if}}

  {{#if @model.record.unavailable_reason}}
    <div class="border rounded p-4 text-center" data-test-record-unavailable>
      <p class="mb-0 text-body-secondary">{{@model.record.unavailable_reason}}</p>
    </div>
  {{else if @model.record.sections}}
    {{#if @model.record.elided}}
      {{! Once, at the top. The reader needs to know the page is not all
      of it, not where each cut fell. }}
      <div class="alert alert-secondary py-2 small" data-test-record-elided-notice>
        This record is large enough that some of it is not drawn below.
      </div>
    {{/if}}

    <div data-test-record>
      {{#each @model.record.sections as |section|}}
        <details class="border rounded p-3 mb-2" open={{unless section.folded true}}>
          <summary class="fw-semibold">
            {{section.key}}

            {{! Only when folded, which is when it is the only thing
            saying what is inside. Over an open section it restates what
            is drawn underneath it. }}
            {{#if section.precis}}
              <span class="text-body-secondary fw-normal ms-2 small">{{section.precis}}</span>
            {{/if}}
          </summary>

          <div class="mt-3">
            <RecordNode @node={{section.node}} />
          </div>
        </details>
      {{/each}}
    </div>
  {{else}}
    <div class="border rounded p-4 text-center">
      <p class="mb-0 text-body-secondary">This record carries nothing under this accession.</p>
    </div>
  {{/if}}
</template> satisfies TOC<{
  Args: {
    model: {
      requestId: number;
      record: AccessionRecord;
    };
  };
}>;
