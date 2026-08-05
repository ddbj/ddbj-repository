import Component from '@glimmer/component';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

import ErrorCode from 'repository/components/error-code';

import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];
type Detail = Validation['details'][number];

interface Signature {
  Args: {
    validation: Validation;
  };
}

interface Group {
  code: string;
  message: string;
  entryIds: string[];
  examples: string;
  count: number;
  truncated: boolean;
}

// How many identifiers a group names before it stops. Enough to
// recognise which records are meant, few enough that a group of four
// hundred does not become the list it is replacing.
const SAMPLES = 3;

// What the check found, said as work rather than as output.
//
// The report used to be one flat table of every finding — entry id, code,
// severity, message — folded into a <details>. Two hundred rows of the
// same eight problems, in a disclosure that had to be opened before
// anything could be learned from it. Grouping by cause is what turns it
// back into a list of things to do.
//
// Errors and warnings are separated because they are different
// instructions: one blocks sending and the other does not, and mixed
// together a submitter works through all of them before daring to
// continue.
export default class ValidationReport extends Component<Signature> {
  @tracked showing: 'error' | 'warning' = 'error';

  get errors() {
    return group(this.args.validation.details.filter((d) => d.severity === 'error'));
  }

  get warnings() {
    return group(this.args.validation.details.filter((d) => d.severity === 'warning'));
  }

  get errorCount() {
    return count(this.errors);
  }

  get warningCount() {
    return count(this.warnings);
  }

  // Errors first when there are any, since those are the ones standing in
  // the way — but a report with only warnings opens on them rather than
  // on an empty tab.
  get visible() {
    return this.showing === 'error' && this.errorCount === 0 && this.warningCount > 0
      ? this.warnings
      : this.showing === 'error'
        ? this.errors
        : this.warnings;
  }

  @action
  show(severity: 'error' | 'warning') {
    this.showing = severity;
  }

  @action
  showErrors() {
    this.show('error');
  }

  @action
  showWarnings() {
    this.show('warning');
  }

  <template>
    <section class="border rounded-3 p-4 mb-4" data-test-validation-report>
      {{! The first question after a failed check is not "how many" — it %}}
      {{! is "did some of it go through". Answered before the count, and %}}
      {{! before anything that looks like a problem. }}
      <p class="mb-3" data-test-nothing-sent>
        <strong>Nothing has been sent to DDBJ.</strong>
        This is still your draft — fix what is below and check it again, as many times as you need.
      </p>

      <div class="btn-group btn-group-sm mb-3" role="group" aria-label="Which findings">
        <button
          type="button"
          class="btn {{if (eq this.showing 'error') 'btn-primary' 'btn-outline-secondary'}}"
          data-test-tab="error"
          {{on "click" this.showErrors}}
        >
          Must fix
          <span class="badge text-bg-light ms-1">{{this.errorCount}}</span>
        </button>

        <button
          type="button"
          class="btn {{if (eq this.showing 'warning') 'btn-primary' 'btn-outline-secondary'}}"
          data-test-tab="warning"
          {{on "click" this.showWarnings}}
        >
          Worth checking
          <span class="badge text-bg-light ms-1">{{this.warningCount}}</span>
        </button>
      </div>

      {{#if this.visible.length}}
        <table class="table align-middle" data-test-findings>
          <thead>
            <tr>
              <th>What to change</th>
              <th>Code</th>
              <th class="text-end">Records</th>
            </tr>
          </thead>

          <tbody>
            {{#each this.visible as |group|}}
              <tr>
                <td>
                  {{group.message}}

                  {{#if group.examples}}
                    <div class="small text-body-secondary">
                      {{group.examples}}{{if group.truncated ", …"}}
                    </div>
                  {{/if}}
                </td>

                {{! The code is how somebody reaches DDBJ's description of }}
                {{! the rule, so it is always there — as a column, not as }}
                {{! the heading. What to change is what gets read first. }}
                <td class="text-nowrap"><ErrorCode @code={{group.code}} /></td>

                <td class="text-end">{{group.count}}</td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      {{else}}
        <p class="text-body-secondary mb-0" data-test-none>
          {{if (eq this.showing "error") "Nothing here needs fixing." "Nothing else worth checking."}}
        </p>
      {{/if}}
    </section>
  </template>
}

// One row per thing to change, rather than one per record it happened to.
// Same code and same message is the same instruction, however many
// records carry it.
function group(details: Detail[]): Group[] {
  const groups = new Map<string, Group>();

  for (const detail of details) {
    const key = JSON.stringify([detail.code, detail.message]);
    const existing = groups.get(key);

    if (existing) {
      existing.count += 1;

      if (detail.entry_id && existing.entryIds.length < SAMPLES) {
        existing.entryIds.push(detail.entry_id);
      } else if (detail.entry_id) {
        existing.truncated = true;
      }
    } else {
      groups.set(key, {
        code: detail.code,
        message: detail.message,
        entryIds: detail.entry_id ? [detail.entry_id] : [],
        examples: '',
        count: 1,
        truncated: false,
      });
    }
  }

  return [...groups.values()]
    .sort((a, b) => b.count - a.count)
    .map((group) => ({ ...group, examples: group.entryIds.join(', ') }));
}

function count(groups: Group[]): number {
  return groups.reduce((total, group) => total + group.count, 0);
}
