import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import Pagination from 'repository/components/pagination';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';

import type Controller from 'repository/controllers/admin/db/submissions';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label="Administration" route="admin")
      (hash label=(dbLabel @model.db) route="admin.db" models=(array @model.db))
      (hash label="Submissions")
    }}
  />

  <h1 class="display-6 mb-4">Submissions ({{dbLabel @model.db}})</h1>

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>ID</th>
        <th>User</th>
        <th>Created</th>
        <th>Updated</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.submissions as |submission|}}
        <tr>
          <td>Submission-{{submission.id}}</td>
          <td>{{submission.user.uid}}</td>
          <td>{{formatDatetime submission.created_at}}</td>
          <td>{{formatDatetime submission.updated_at}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  <Pagination
    @route="admin.db.submissions"
    @models={{array @model.db}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      db: string;
      submissions: components['schemas']['AdminSubmissionSummary'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
