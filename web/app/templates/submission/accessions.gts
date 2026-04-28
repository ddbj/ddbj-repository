import { array, concat, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import Pagination from 'repository/components/pagination';
import dbLabel from 'repository/helpers/db-label';

import type Controller from 'repository/controllers/submission/accessions';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label=(dbLabel @model.db) route="db" models=(array @model.db))
      (hash label="Submissions" route="db.submissions" models=(array @model.db))
      (hash
        label=(concat "Submission-" @model.submission_id)
        route="submission"
        models=(array @model.db @model.submission_id)
      )
      (hash label="Accessions")
    }}
  />

  <h1 class="display-6 mb-4">Accessions</h1>

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>Accession</th>
        <th>Entry ID</th>
        <th>Version</th>
        <th>LOCUS Date</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.accessions as |accession|}}
        <tr>
          <td>{{accession.number}}</td>
          <td>{{accession.entry_id}}</td>
          <td>{{accession.version}}</td>
          <td>{{accession.locus_date}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  <Pagination
    @route="submission.accessions"
    @models={{array @model.db @model.submission_id}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      db: string;
      submission_id: string;
      accessions: components['schemas']['Accession'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
