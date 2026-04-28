import { LinkTo } from '@ember/routing';
import { array } from '@ember/helper';

import Pagination from 'repository/components/pagination';
import StatusBadge from 'repository/components/status-badge';
import formatDatetime from 'repository/helpers/format-datetime';

import type Controller from 'repository/controllers/db/requests/index';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <h1 class="display-6 mb-4">Requests ({{@model.db}})</h1>

  <div class="mb-3">
    <LinkTo @route="db.requests.new" @model={{@model.db}} class="btn btn-primary">New Submission Request</LinkTo>
  </div>

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>ID</th>
        <th>Created</th>
        <th>Status</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.requests as |request|}}
        <tr>
          <td>
            <LinkTo @route="request" @models={{array @model.db request.id}}>
              Request-{{request.id}}
            </LinkTo>
          </td>

          <td>{{formatDatetime request.created_at}}</td>
          <td><StatusBadge @status={{request.status}} /></td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  <Pagination
    @route="db.requests.index"
    @models={{array @model.db}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      db: string;
      requests: components['schemas']['SubmissionRequestSummary'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
