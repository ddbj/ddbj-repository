import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';

import { or, notEq } from 'ember-truth-helpers';

import Pagination from 'repository/components/pagination';
import ProgressLabel from 'repository/components/progress-label';
import ResultBadge from 'repository/components/result-badge';
import SubmissionsSearchForm from 'repository/components/submissions-search-form';
import Table from 'repository/components/table';
import formatDatetime from 'repository/helpers/format-datetime';

import type SubmissionsIndexController from 'repository/controllers/submissions/index';
import type { Model } from 'repository/routes/submissions/index';
import type { Query } from 'repository/components/submissions-search-form';

interface Signature {
  Args: {
    model: Model;
    controller: SubmissionsIndexController;
  };
}

export default class extends Component<Signature> {
  @action
  applyQuery(query: Query) {
    const { controller } = this.args;

    Object.assign(controller, query, { page: 1 });
  }

  <template>
    <h1 class="display-6 mb-4">Submissions</h1>

    <SubmissionsSearchForm @onChange={{this.applyQuery}} class="bg-light p-3 border rounded" />

    <Table @items={{@model.submissions}}>
      <thead class="table-light">
        <tr>
          <th>ID</th>
          <th>DB</th>
          <th>Created</th>
          <th>Started</th>
          <th>Finished</th>
          <th>Progress</th>
          <th>Result</th>
          <th>Validation</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.submissions key="id" as |submission|}}
          <tr>
            <td>
              <LinkTo @route="submission" @model={{submission}}>{{submission.id}}</LinkTo>
            </td>

            <td>{{submission.validation.db}}</td>
            <td>{{formatDatetime submission.created_at}}</td>

            <td>
              {{#if submission.started_at}}
                {{formatDatetime submission.started_at}}
              {{else}}
                -
              {{/if}}
            </td>

            <td>
              {{#if submission.finished_at}}
                {{formatDatetime submission.finished_at}}
              {{else}}
                -
              {{/if}}
            </td>

            <td>
              <ProgressLabel @progress={{submission.progress}} />
            </td>

            <td>
              <ResultBadge @result={{submission.result}} />
            </td>

            <td>
              <LinkTo
                @route="validation"
                @model={{submission.validation}}
              >#{{submission.validation.id}}</LinkTo>
            </td>
          </tr>
        {{/each}}
      </tbody>
    </Table>

    {{#if (notEq @model.totalPages 1)}}
      <Pagination @route="submissions.index" @current={{or @controller.page 1}} @total={{@model.totalPages}} />
    {{/if}}
  </template>
}
