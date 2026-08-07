import { LinkTo } from '@ember/routing';

import Pagination from 'repository/components/pagination';

import type Controller from 'repository/controllers/review/accessions';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <LinkTo @route="review" @model={{@model.token}}>&larr; Back</LinkTo>

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
          <td>{{accession.accession}}</td>
          <td>{{accession.entry_id}}</td>
          <td>{{accession.version}}</td>
          <td>{{accession.locus_date}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  <Pagination
    @route="review.accessions"
    @models={{array @model.token}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      token: string;
      accessions: components['schemas']['ReviewerAccession'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
