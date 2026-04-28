import { LinkTo } from '@ember/routing';
import { array } from '@ember/helper';

import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

<template>
  <h1 class="display-6 mb-4">Submission-{{@model.id}}</h1>

  <dl class="horizontal">
    <dt>Created</dt>
    <dd>{{formatDatetime @model.created_at}}</dd>

    <dt>Updated</dt>
    <dd>{{formatDatetime @model.updated_at}}</dd>

    <dt>DDBJ Record</dt>

    <dd>
      <a href={{@model.ddbj_record.url}} target="_blank" rel="noopener noreferrer">
        {{@model.ddbj_record.filename}}
      </a>
    </dd>

    <dt>Flatfile (NA)</dt>

    <dd>
      {{#if @model.flatfile_na}}
        <a href={{@model.flatfile_na.url}} target="_blank" rel="noopener noreferrer">
          {{@model.flatfile_na.filename}}
        </a>
      {{else}}
        -
      {{/if}}
    </dd>

    <dt>Flatfile (AA)</dt>

    <dd>
      {{#if @model.flatfile_aa}}
        <a href={{@model.flatfile_aa.url}} target="_blank" rel="noopener noreferrer">
          {{@model.flatfile_aa.filename}}
        </a>
      {{else}}
        -
      {{/if}}
    </dd>
  </dl>

  <div class="my-3">
    <LinkTo @route="submission.accessions">Accessions</LinkTo>
  </div>

  <h2 class="mt-3">Updates</h2>

  <div class="my-3">
    <LinkTo @route="submission.updates.new" class="btn btn-primary">Update Submission</LinkTo>
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
      {{#each @model.updates as |update|}}
        <tr>
          <td>
            <LinkTo @route="update" @models={{array @model.db update.id}}>
              Update-{{update.id}}
            </LinkTo>
          </td>

          <td>{{formatDatetime update.created_at}}</td>
          <td>{{update.status}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>
</template> satisfies TOC<{
  Args: {
    model: { db: string } & components['schemas']['Submission'];
  };
}>;
