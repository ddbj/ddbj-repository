import { LinkTo } from '@ember/routing';

import formatDatetime from 'repository/helpers/format-datetime';
import Pagination from 'repository/components/pagination';

import type Controller from 'repository/controllers/submission/accessions';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <h1 class="display-6 mb-4">Accessions</h1>

  <div class="mb-3">
    <LinkTo @route="submission">&larr; Back to Submission</LinkTo>
  </div>

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>Accession</th>
        <th>Entry ID</th>
        <th>Version</th>
        <th>Last Updated</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.accessions as |accession|}}
        <tr>
          <td>{{accession.number}}</td>
          <td>{{accession.entry_id}}</td>
          <td>{{accession.version}}</td>
          <td>{{formatDatetime accession.last_updated_at}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  <Pagination @route="submission.accessions" @current={{@controller.page}} @total={{@model.totalPages}} />
</template> satisfies TOC<{
  Args: {
    model: {
      accessions: components['schemas']['Accession'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
