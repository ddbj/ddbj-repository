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

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>Accession</th>
        <th>Entry ID</th>
        <th>Version</th>
        <th>LOCUS Date</th>
        <th>Status</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.accessions as |accession|}}
        <tr>
          <td>{{accession.accession}}</td>
          <td>{{accession.entry_id}}</td>
          <td>{{accession.version}}</td>
          <td>{{accession.locus_date}}</td>
          <td>{{accession.status}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

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
      accessions: components['schemas']['Accession'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
