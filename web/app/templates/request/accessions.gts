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

  {{! One table for three databases. A BioProject has a title and a type,
  a BioSample an organism and a package, an ST.26 entry a version and a
  LOCUS date — so what each record states beyond its number travels as
  labelled facts rather than as a column per database, and the table does
  not grow a column the other two leave empty. }}
  <div class="table-responsive">
    <table class="table border align-middle" data-test-accessions>
      <thead class="table-light">
        <tr>
          <th scope="col">Accession</th>
          <th scope="col">Name</th>
          <th scope="col">Details</th>
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

            <td class="small">
              {{#each accession.details as |detail|}}
                <div>
                  <span class="text-body-secondary">{{detail.label}}</span>
                  {{detail.value}}
                </div>
              {{/each}}
            </td>

            {{! Plain text, as it was. StatusBadge speaks the request's
            vocabulary (validating, applied) and this is the record's
            (curating, public, withdrawn); giving the second one a palette
            is a decision this change does not need to make. }}
            <td class="text-capitalize">{{accession.status}}</td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  </div>

  <Pagination
    @route="request.accessions"
    @models={{array @model.requestId}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      db: string;
      requestId: number;
      submissionId: number | undefined;
      accessions: components['schemas']['SubmissionAccession'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
