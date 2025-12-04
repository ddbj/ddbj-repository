import { LinkTo } from '@ember/routing';

import formatDatetime from 'repository/helpers/format-datetime';

<template>
  <h1>Update-{{@model.id}}</h1>

  <dl class="horizontal">
    <dt>Submission</dt>

    <dd>
      <LinkTo @route="submission" @model={{@model.submission.id}}>Submission-{{@model.submission.id}}</LinkTo>
    </dd>

    <dt>Created</dt>
    <dd>{{formatDatetime @model.created_at}}</dd>

    <dt>File</dt>

    <dd>
      <a href={{@model.ddbj_record.url}} target="_blank" rel="noopener noreferrer">{{@model.ddbj_record.filename}}</a>
    </dd>

    <dt>Status</dt>
    <dd>{{@model.status}}</dd>

    {{#if @model.error_message}}
      <dt>Error</dt>
      <dd>{{@model.error_message}}</dd>
    {{/if}}
  </dl>

  <h2>Validation</h2>

  <dl class="horizontal">
    <dt>Progress</dt>
    <dd>{{@model.validation.progress}}</dd>

    <dt>Started</dt>
    <dd>{{formatDatetime @model.validation.created_at}}</dd>

    <dt>Finished</dt>
    <dd>{{formatDatetime @model.validation.finished_at}}</dd>

    <dt>Validity</dt>
    <dd>{{@model.validation.validity}}</dd>
  </dl>

  <details class="my-3">
    <summary>Details</summary>

    <table class="table">
      <thead>
        <tr>
          <th>Filename</th>
          <th>Entry ID</th>
          <th>Code</th>
          <th>Severity</th>
          <th>Message</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.validation.details as |detail|}}
          <tr>
            <td>{{detail.filename}}</td>
            <td>{{detail.entry_id}}</td>
            <td>{{detail.code}}</td>
            <td>{{detail.severity}}</td>
            <td>{{detail.message}}</td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  </details>
</template>
