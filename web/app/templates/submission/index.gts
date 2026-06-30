import { LinkTo } from '@ember/routing';
import { array, concat, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import SubmissionMessages from 'repository/components/submission-messages';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

<template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label=(dbLabel @model.db) route="db" models=(array @model.db))
      (hash label="Submissions" route="db.submissions" models=(array @model.db))
      (hash label=(concat "Submission-" @model.id))
    }}
  />

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

  <SubmissionMessages @submissionId={{@model.id}} />
</template> satisfies TOC<{
  Args: {
    model: { db: string } & components['schemas']['Submission'];
  };
}>;
