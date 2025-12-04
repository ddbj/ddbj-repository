import { LinkTo } from '@ember/routing';

import formatDatetime from 'repository/helpers/format-datetime';

<template>
  <h1>Submission-{{@model.id}}</h1>

  <dl class="horizontal">
    <dt>File</dt>

    <dd>
      {{#if @model.ddbj_record}}
        <a href={{@model.ddbj_record.url}} target="_blank" rel="noopener noreferrer">
          {{@model.ddbj_record.filename}}
        </a>
      {{/if}}
    </dd>
  </dl>

  <details>
    <summary>Accessions</summary>

    <table class="table">
      <thead>
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
  </details>

  <h2 class="mt-3">Updates</h2>

  <div class="my-3">
    <LinkTo @route="updates.new" class="btn btn-primary">Update Submission</LinkTo>
  </div>

  <table class="table">
    <thead>
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
            <LinkTo @route="update" @model={{update.id}}>
              Update-{{update.id}}
            </LinkTo>
          </td>

          <td>{{formatDatetime update.created_at}}</td>
          <td>{{update.status}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>
</template>
