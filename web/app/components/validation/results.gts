import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { eq } from 'ember-truth-helpers';
import { sub } from 'ember-math-helpers';

import ErrorCode from 'repository/components/error-code';
import ValidityBadge from 'repository/components/validity-badge';

import type RequestService from 'repository/services/request';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    showUser?: boolean;
    validation: Validation;
  };
}

export default class ValidationResults extends Component<Signature> {
  @service declare request: RequestService;

  @action
  async downloadFile(url: string) {
    await this.request.downloadFile(url);
  }

  <template>
    <table class="table">
      <thead>
        <tr>
          <th>Object</th>
          <th>File</th>
          <th>Validity</th>
          <th>Details</th>
        </tr>
      </thead>

      <tbody>
        {{#each @validation.results key="object_id" as |result|}}
          <tr>
            <td>{{result.object_id}}</td>

            <td>
              {{#if result.file}}
                <button
                  type="button"
                  class="btn btn-link p-0"
                  {{on "click" (fn this.downloadFile result.file.url)}}
                >{{result.file.path}}</button>
              {{else}}
                -
              {{/if}}
            </td>

            <td><ValidityBadge @validity={{result.validity}} /></td>

            <td class="p-0">
              {{#if result.details}}
                <table class="table m-0">
                  <thead>
                    <tr>
                      <th>Code</th>
                      <th>Severity</th>
                      <th>Message</th>
                    </tr>
                  </thead>

                  <tbody>
                    {{#each result.details as |detail i|}}
                      <tr>
                        {{#let (eq i (sub result.details.length 1)) as |isLast|}}
                          <td class={{if isLast "border-bottom-0"}}>
                            <ErrorCode @code={{detail.code}} />
                          </td>

                          <td class={{if isLast "border-bottom-0"}}>
                            {{if detail.severity detail.severity "-"}}
                          </td>

                          <td class={{if isLast "border-bottom-0"}}>
                            {{detail.message}}
                          </td>
                        {{/let}}
                      </tr>
                    {{/each}}
                  </tbody>
                </table>
              {{else}}
                -
              {{/if}}
            </td>
          </tr>
        {{/each}}
      </tbody>
    </table>

    {{#if @validation.raw_result}}
      <details>
        <summary>Raw result</summary>
        <pre><code>{{globalThis.JSON.stringify @validation.raw_result null 2}}</code></pre>
      </details>
    {{/if}}
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'Validation::Results': typeof ValidationResults;
  }
}
