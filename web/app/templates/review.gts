import { pageTitle } from 'ember-page-title';

import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Review = components['schemas']['Review'];

// What a share link shows. Deliberately not the submitter's screen with
// controls removed: there is no submission here, no conversation and no
// owner — a reviewer was given some records, not a collaboration.
//
// And nothing to download. The link is granted per accession, and a
// record or a flatfile is the whole submission the accession came from,
// which is the thing that was deliberately not shared — so what each
// record says is drawn on the page instead.
export default <template>
  {{pageTitle @model.name}}

  <div class="alert alert-info py-2 small" role="note">
    You are looking at data shared with you through a link. No account is needed, and nothing here can be changed.
  </div>

  <h1 class="display-6 mb-1">{{@model.name}}</h1>

  <p class="text-body-secondary small mb-4">
    This link stops working on
    {{formatDatetime @model.expires_at}}.
  </p>

  {{#if @model.accessions}}
    <div class="table-responsive">
      <table class="table border align-middle" data-test-accessions>
        <thead class="table-light">
          <tr>
            <th scope="col">Accession</th>
            <th scope="col">Database</th>
            <th scope="col">Name</th>
            <th scope="col">Details</th>
          </tr>
        </thead>

        <tbody>
          {{#each @model.accessions as |accession|}}
            <tr>
              <td class="font-monospace">{{accession.accession}}</td>
              <td>{{dbLabel accession.db}}</td>

              <td>
                {{#if accession.name}}
                  {{accession.name}}
                {{else}}
                  <span class="text-body-tertiary">—</span>
                {{/if}}
              </td>

              {{! Whatever this record carries, in its own words. Three
              databases keep three different rows, so the column is a list
              of labelled facts rather than one column per database. }}
              <td class="small">
                {{#each accession.details as |detail|}}
                  <div>
                    <span class="text-body-secondary">{{detail.label}}</span>
                    {{detail.value}}
                  </div>
                {{/each}}
              </td>
            </tr>
          {{/each}}
        </tbody>
      </table>
    </div>
  {{else}}
    <div class="border rounded p-4 text-center">
      <p class="mb-1 fw-semibold">Nothing has been put on this link yet.</p>

      <p class="text-body-secondary small mb-0">
        Whoever sent it to you names the accessions it carries, so ask them to add the ones you are meant to see.
      </p>
    </div>
  {{/if}}
</template> satisfies TOC<{
  Args: {
    model: Review;
  };
}>;
