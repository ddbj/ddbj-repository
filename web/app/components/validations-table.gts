import { LinkTo } from '@ember/routing';

import { notEq } from 'ember-truth-helpers';

import DetailsCount from 'repository/components/details-count';
import Pagination from 'repository/components/pagination';
import ProgressLabel from 'repository/components/progress-label';
import Table from 'repository/components/table';
import ValidityBadge from 'repository/components/validity-badge';
import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    showUser?: boolean;
    validations: Validation[];
    page: number;
    lastPage: number;
    indexRoute: string;
    showRoute: string;
  };
}

export default <template>
  <Table @items={{@validations}}>
    <thead class="table-light">
      <tr>
        <th>ID</th>

        {{#if @showUser}}
          <th>User</th>
        {{/if}}

        <th>DB</th>
        <th>Created</th>
        <th>Started</th>
        <th>Finished</th>
        <th>Progress</th>
        <th>Validity</th>
        <th>Submission</th>
      </tr>
    </thead>

    <tbody>
      {{#each @validations key="id" as |validation|}}
        <tr>
          <td class="position-relative">
            <LinkTo @route={{@showRoute}} @model={{validation}} class="stretched-link">
              {{validation.id}}
            </LinkTo>
          </td>

          {{#if @showUser}}
            <td>{{validation.user.uid}}</td>
          {{/if}}

          <td>{{validation.db}}</td>
          <td>{{formatDatetime validation.created_at}}</td>

          <td>
            {{#if validation.started_at}}
              {{formatDatetime validation.started_at}}
            {{else}}
              -
            {{/if}}
          </td>

          <td>
            {{#if validation.finished_at}}
              {{formatDatetime validation.finished_at}}
            {{else}}
              -
            {{/if}}
          </td>

          <td><ProgressLabel @progress={{validation.progress}} /></td>

          <td>
            <ValidityBadge @validity={{validation.validity}} />
            <DetailsCount @results={{validation.results}} />
          </td>

          <td class="position-relative">
            {{#if validation.submission}}
              <LinkTo @route="submissions.show" @model={{validation.submission.id}} class="stretched-link">
                {{validation.submission.id}}
              </LinkTo>
            {{else}}
              -
            {{/if}}
          </td>
        </tr>
      {{/each}}
    </tbody>
  </Table>

  {{#if (notEq @lastPage 1)}}
    <Pagination @route={{@indexRoute}} @current={{@page}} @last={{@lastPage}} />
  {{/if}}
</template> satisfies TOC<Signature>;
