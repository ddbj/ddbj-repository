import Component from '@glimmer/component';
import { action } from '@ember/object';
import { array, hash } from '@ember/helper';

import AdminListFilter from 'repository/components/admin/list-filter';
import Breadcrumb from 'repository/components/breadcrumb';
import Pagination from 'repository/components/pagination';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';

import type Controller from 'repository/controllers/admin/submissions';
import type { components } from 'schema/openapi';

type Model = {
  submissions: components['schemas']['AdminSubmissionSummary'][];
  totalPages: number;
};

class AdminSubmissions extends Component<{ Args: { model: Model; controller: Controller } }> {
  @action
  apply({ db, user }: { db: string; user: string }) {
    this.args.controller.db = db;
    this.args.controller.user = user;
    this.args.controller.page = 1;
  }

  <template>
    <Breadcrumb
      @items={{array
        (hash label="Home" route="index")
        (hash label="Administration" route="admin")
        (hash label="Submissions")
      }}
    />

    <h1 class="display-6 mb-4">Submissions</h1>

    <AdminListFilter @db={{@controller.db}} @user={{@controller.user}} @onApply={{this.apply}} />

    <table class="table border">
      <thead class="table-light">
        <tr>
          <th>ID</th>
          <th>Database</th>
          <th>User</th>
          <th>Created</th>
          <th>Updated</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.submissions as |submission|}}
          <tr>
            <td>Submission-{{submission.id}}</td>
            <td>{{dbLabel submission.db}}</td>
            <td>{{submission.user.uid}}</td>
            <td>{{formatDatetime submission.created_at}}</td>
            <td>{{formatDatetime submission.updated_at}}</td>
          </tr>
        {{else}}
          <tr>
            <td colspan="5" class="text-center text-body-secondary py-4">No submissions found.</td>
          </tr>
        {{/each}}
      </tbody>
    </table>

    <Pagination @route="admin.submissions" @current={{@controller.page}} @total={{@model.totalPages}} />
  </template>
}

export default AdminSubmissions;
