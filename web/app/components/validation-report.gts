import Component from '@glimmer/component';
import { action } from '@ember/object';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

import ErrorCode from 'repository/components/error-code';

import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];
type Detail = Validation['details'][number];
type Severity = Detail['severity'];

interface Signature {
  Args: {
    validation: Validation;
  };
}

interface Group {
  code: string;
  message: string;
  examples: string;
  count: number;
  truncated: boolean;
}

// How many identifiers a group names before it stops. Enough to
// recognise which records are meant, few enough that a group of four
// hundred becomes the list it is replacing — the whole list is still a
// disclosure away.
const SAMPLES = 3;

// What the check found, said as work rather than as output.
//
// The report used to be one flat table of every finding — entry id, code,
// severity, message — folded into a <details>. Two hundred rows of the
// same eight problems, in a disclosure that had to be opened before
// anything could be learned from it. Grouping by cause is what turns it
// back into a list of things to do; the flat table stays underneath,
// folded, because three example ids out of ten is a summary and somebody
// correcting the file needs the other seven.
//
// Errors and warnings are separated because they are different
// instructions: one blocks sending and the other does not, and mixed
// together a submitter works through all of them before daring to
// continue.
export default class ValidationReport extends Component<Signature> {
  @tracked chosen: Severity | null = null;

  // Once per render rather than once per reader. `visible` is read twice
  // by the template and the counts by both tabs, and each of those passes
  // filtered the whole list and built a key per detail. Findings are not
  // capped, so a BioSample submission can arrive with tens of thousands.
  @cached
  get groups() {
    const errors: Detail[] = [];
    const warnings: Detail[] = [];

    for (const detail of this.args.validation.details) {
      (detail.severity === 'error' ? errors : warnings).push(detail);
    }

    return {
      error: group(errors),
      warning: group(warnings),
      errorCount: errors.length,
      warningCount: warnings.length,
    };
  }

  // Errors are what stand in the way, so they open — unless there are
  // none, in which case opening on an empty tab would be a report hiding
  // its only content. Derived rather than corrected further down, so the
  // highlighted tab and the table under it cannot disagree.
  get showing(): Severity {
    return this.chosen ?? (this.groups.errorCount > 0 ? 'error' : 'warning');
  }

  get visible() {
    return this.groups[this.showing];
  }

  @action
  showErrors() {
    this.chosen = 'error';
  }

  @action
  showWarnings() {
    this.chosen = 'warning';
  }

  <template>
    <section class="border rounded-3 p-4 mb-4" data-test-validation-report>
      {{! The first question after a failed check is not "how many" — it }}
      {{! is "did some of it go through". Answered before the count, and }}
      {{! before anything that looks like a problem. }}
      <p class="mb-3" data-test-nothing-sent>
        <strong>Nothing has been sent to DDBJ.</strong>
        This is still your draft — fix what is below and check it again, as many times as you need.
      </p>

      {{! Which set is showing is said to the accessibility tree as well as }}
      {{! in the styling: colour alone leaves a screen reader with two }}
      {{! counts and no way to tell which table is underneath. }}
      <div class="btn-group btn-group-sm mb-3" role="group" aria-label="Which findings">
        <button
          type="button"
          class="btn {{if (eq this.showing 'error') 'btn-primary' 'btn-outline-secondary'}}"
          aria-pressed="{{eq this.showing 'error'}}"
          data-test-tab="error"
          {{on "click" this.showErrors}}
        >
          Must fix
          <span class="badge text-bg-light ms-1">{{this.groups.errorCount}}</span>
        </button>

        <button
          type="button"
          class="btn {{if (eq this.showing 'warning') 'btn-primary' 'btn-outline-secondary'}}"
          aria-pressed="{{eq this.showing 'warning'}}"
          data-test-tab="warning"
          {{on "click" this.showWarnings}}
        >
          Worth checking
          <span class="badge text-bg-light ms-1">{{this.groups.warningCount}}</span>
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
            {{#each this.visible as |finding|}}
              <tr>
                <td>
                  {{finding.message}}

                  {{#if finding.examples}}
                    <div class="small text-body-secondary">
                      {{finding.examples}}{{if finding.truncated ", …"}}
                    </div>
                  {{/if}}
                </td>

                {{! The code is how somebody reaches DDBJ's description of }}
                {{! the rule, so it is always there — as a column, not as }}
                {{! the heading. What to change is what gets read first. }}
                <td class="text-nowrap"><ErrorCode @code={{finding.code}} /></td>

                <td class="text-end">{{finding.count}}</td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      {{else}}
        <p class="text-body-secondary mb-0" data-test-none>
          {{if (eq this.showing "error") "Nothing here needs fixing." "Nothing else worth checking."}}
        </p>
      {{/if}}

      {{! Three example ids out of ten is a summary. Whoever is correcting }}
      {{! the file needs the other seven, and once the grouped report is on }}
      {{! screen this is the only place in the web client that has them. }}
      {{! template-lint-disable no-nested-interactive }}
      <details class="mt-3" data-test-every-finding>
        <summary class="small text-body-secondary">Every finding ({{@validation.details.length}})</summary>

        <table class="table table-sm mt-2">
          <thead>
            <tr>
              <th>Entry ID</th>
              <th>Code</th>
              <th>Severity</th>
              <th>Message</th>
            </tr>
          </thead>

          <tbody>
            {{#each @validation.details as |detail|}}
              <tr>
                <td>{{detail.entry_id}}</td>
                <td><ErrorCode @code={{detail.code}} /></td>
                <td>{{detail.severity}}</td>
                <td>{{detail.message}}</td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      </details>
    </section>
  </template>
}

interface Bucket {
  code: string;
  message: string;
  entryIds: string[];
  withIds: number;
  count: number;
}

// One row per thing to change, rather than one per record it happened to.
// Same code and same message is the same instruction, however many
// records carry it.
function group(details: Detail[]): Group[] {
  const buckets = new Map<string, Bucket>();

  for (const detail of details) {
    const key = JSON.stringify([detail.code, detail.message]);
    const bucket = buckets.get(key) ?? {
      code: detail.code,
      message: detail.message,
      entryIds: [],
      withIds: 0,
      count: 0,
    };

    bucket.count += 1;

    if (detail.entry_id) {
      bucket.withIds += 1;

      if (bucket.entryIds.length < SAMPLES) bucket.entryIds.push(detail.entry_id);
    }

    buckets.set(key, bucket);
  }

  return [...buckets.values()]
    .sort((a, b) => b.count - a.count)
    .map(({ code, message, entryIds, withIds, count }) => ({
      code,
      message,
      count,
      examples: entryIds.join(', '),
      // Against the number that carried an id, not against the total: a
      // group mixing file-level and entry-level findings would otherwise
      // list two examples and read as though they were all of them.
      truncated: withIds > entryIds.length,
    }));
}
