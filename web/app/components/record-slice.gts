import RecordNode from 'repository/components/record-node';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type RecordSlice = components['schemas']['RecordSlice'];

// One accessioned row's record, laid out by the shape of the data.
// Nothing here names a field — a new v3 key appears the day it lands
// rather than the day somebody revises this.
//
// Drawn identically for the submitter reading their own record and for a
// reviewer holding a share link. What differs between those two screens
// is what they put around it, which is why that is where they differ and
// this is one component.
export default <template>
  {{#if @record.unavailable_reason}}
    <div class="border rounded p-4 text-center" data-test-record-unavailable>
      <p class="mb-0 text-body-secondary">{{@record.unavailable_reason}}</p>
    </div>
  {{else if @record.sections}}
    {{#if @record.elided}}
      {{! Once, at the top. The reader needs to know the page is not all
      of it, not where each cut fell. }}
      <div class="alert alert-secondary py-2 small" data-test-record-elided-notice>
        This record is large enough that some of it is not drawn below.
      </div>
    {{/if}}

    <div data-test-record>
      {{#each @record.sections as |section|}}
        <details class="border rounded p-3 mb-2" open={{unless section.folded true}}>
          <summary class="fw-semibold">
            {{section.key}}

            {{! Only when folded, which is when it is the only thing
            saying what is inside. Over an open section it restates what
            is drawn underneath it. }}
            {{#if section.precis}}
              <span class="text-body-secondary fw-normal ms-2 small">{{section.precis}}</span>
            {{/if}}
          </summary>

          <div class="mt-3">
            <RecordNode @node={{section.node}} />
          </div>
        </details>
      {{/each}}
    </div>
  {{else}}
    <div class="border rounded p-4 text-center">
      <p class="mb-0 text-body-secondary">This record carries nothing under this accession.</p>
    </div>
  {{/if}}
</template> satisfies TOC<{
  Args: {
    record: RecordSlice;
  };
}>;
