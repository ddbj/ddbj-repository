import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import Pagination from 'repository/components/pagination';
import StatusBadge from 'repository/components/status-badge';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';

import type Controller from 'repository/controllers/admin/db/requests';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label="Administration" route="admin")
      (hash label=(dbLabel @model.db) route="admin.db" models=(array @model.db))
      (hash label="Requests")
    }}
  />

  <h1 class="display-6 mb-4">Requests ({{dbLabel @model.db}})</h1>

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>ID</th>
        <th>User</th>
        <th>Created</th>
        <th>Status</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.requests as |request|}}
        <tr>
          <td>Request-{{request.id}}</td>
          <td>{{request.user.uid}}</td>
          <td>{{formatDatetime request.created_at}}</td>
          <td><StatusBadge @status={{request.status}} /></td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  <Pagination
    @route="admin.db.requests"
    @models={{array @model.db}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      db: string;
      requests: components['schemas']['AdminSubmissionRequestSummary'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
