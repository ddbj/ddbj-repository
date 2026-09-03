import { concat } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import Pagination from 'repository/components/pagination';

import type Controller from 'repository/controllers/request/accessions';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label=(concat "#" @model.requestId) route="request" model=@model.requestId)
      (hash label="Accessions")
    }}
  />

  <h1 class="display-6 mb-4">Accessions</h1>

  {{#if @model.accessions}}
    {{! One table, and its middle columns come from the rows. What each
    record states arrives as labelled facts — a review link can hold all
    three databases at once and they agree on nothing past a name — but a
    submission is one database, so here the labels are the same on every
    row and can be columns. That is what lets a LOCUS date be read down
    one rather than restated on every line. }}
    <div class="table-responsive">
      <table class="table border align-middle" data-test-accessions>
        <thead class="table-light">
          <tr>
            <th scope="col">Accession</th>
            <th scope="col">Name</th>

            {{#each @controller.columns as |label|}}
              <th scope="col">{{label}}</th>
            {{/each}}

            <th scope="col">Status</th>
          </tr>
        </thead>

        <tbody>
          {{#each @model.accessions as |accession|}}
            <tr>
              <td class="font-monospace">{{accession.accession}}</td>

              <td>
                {{#if accession.name}}
                  {{accession.name}}
                {{else}}
                  <span class="text-body-tertiary">—</span>
                {{/if}}
              </td>

              {{#each (@controller.detailsFor accession) as |value|}}
                <td>
                  {{#if value}}
                    {{value}}
                  {{else}}
                    <span class="text-body-tertiary">—</span>
                  {{/if}}
                </td>
              {{/each}}

              {{! Plain text. StatusBadge speaks the request's vocabulary
              (validating, applied) and this is the record's (curating,
              public, withdrawn); giving the second one a palette is a
              decision this change does not need to make. }}
              <td class="text-capitalize">{{accession.status}}</td>
            </tr>
          {{/each}}
        </tbody>
      </table>
    </div>
  {{else}}
    {{! Ordinary rather than impossible: a BioProject or BioSample
    submission has no numbers until they are issued. }}
    <div class="border rounded p-4 text-center">
      <p class="mb-1 fw-semibold">No accessions yet.</p>

      <p class="text-body-secondary small mb-0">
        DDBJ issues them once the submission has been through curation. They will appear here.
      </p>
    </div>
  {{/if}}

  <Pagination
    @route="request.accessions"
    @models={{array @model.requestId}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      requestId: number;
      accessions: components['schemas']['SubmissionAccession'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
