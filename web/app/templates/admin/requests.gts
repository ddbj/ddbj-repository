import Component from '@glimmer/component';
import { action } from '@ember/object';
import { array, hash } from '@ember/helper';

import AdminListFilter from 'repository/components/admin/list-filter';
import Breadcrumb from 'repository/components/breadcrumb';
import Pagination from 'repository/components/pagination';
import StatusBadge from 'repository/components/status-badge';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';

import type Controller from 'repository/controllers/admin/requests';
import type { components } from 'schema/openapi';

type Model = {
  requests: components['schemas']['AdminSubmissionRequestSummary'][];
  totalPages: number;
};

class AdminRequests extends Component<{ Args: { model: Model; controller: Controller } }> {
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
        (hash label="Submission requests")
      }}
    />

    <h1 class="display-6 mb-4">Submission requests</h1>

    <AdminListFilter @db={{@controller.db}} @user={{@controller.user}} @onApply={{this.apply}} />

    <table class="table border">
      <thead class="table-light">
        <tr>
          <th>ID</th>
          <th>Database</th>
          <th>User</th>
          <th>Created</th>
          <th>Status</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.requests as |request|}}
          <tr>
            <td>Request-{{request.id}}</td>
            <td>{{dbLabel request.db}}</td>
            <td>{{request.user.uid}}</td>
            <td>{{formatDatetime request.created_at}}</td>
            <td><StatusBadge @status={{request.status}} /></td>
          </tr>
        {{else}}
          <tr>
            <td colspan="5" class="text-center text-body-secondary py-4">No requests found.</td>
          </tr>
        {{/each}}
      </tbody>
    </table>

    <Pagination @route="admin.requests" @current={{@controller.page}} @total={{@model.totalPages}} />
  </template>
}

export default AdminRequests;
