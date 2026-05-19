import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { array, hash, uniqueId } from '@ember/helper';

import { eq } from 'ember-truth-helpers';

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
  filter(e: Event) {
    e.preventDefault();

    const data = new FormData(e.target as HTMLFormElement);
    const text = (key: string) => {
      const value = data.get(key);
      return typeof value === 'string' ? value : '';
    };

    this.args.controller.db = text('db');
    this.args.controller.user = text('user');
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

    <form class="row g-2 mb-3" {{on "submit" this.filter}}>
      {{#let (uniqueId) (uniqueId) as |dbId userId|}}
        <div class="col-sm-4">
          <label for={{dbId}} class="form-label visually-hidden">Database</label>

          <select name="db" id={{dbId}} class="form-select">
            <option value="" selected={{eq @controller.db ""}}>All databases</option>
            <option value="st26" selected={{eq @controller.db "st26"}}>ST.26</option>
            <option value="bioproject" selected={{eq @controller.db "bioproject"}}>BioProject</option>
            <option value="biosample" selected={{eq @controller.db "biosample"}}>BioSample</option>
          </select>
        </div>

        <div class="col-sm-6">
          <label for={{userId}} class="form-label visually-hidden">User uid</label>

          <input
            type="search"
            name="user"
            id={{userId}}
            value={{@controller.user}}
            class="form-control"
            placeholder="Filter by user uid"
          />
        </div>

        <div class="col-sm-2">
          <button type="submit" class="btn btn-primary w-100">Filter</button>
        </div>
      {{/let}}
    </form>

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
