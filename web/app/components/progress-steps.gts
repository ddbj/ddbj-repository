import Component from '@glimmer/component';

import type { components } from 'schema/openapi';

type Progress = components['schemas']['Progress'];
type Step = Progress['step'];

interface Signature {
  Args: {
    progress: Progress;
  };
}

// The six steps the server derives (CurationState::STEPS), labelled for a
// submitter. The vocabulary is fixed, so only the position travels over
// the wire.
const STEPS: { key: Step; label: string }[] = [
  { key: 'submitted', label: 'Submitted' },
  { key: 'validated', label: 'Validated' },
  { key: 'applied', label: 'Accepted by DDBJ' },
  { key: 'curating', label: 'In curation' },
  { key: 'accession_issued', label: 'Accessions issued' },
  { key: 'public', label: 'Public' },
];

export default class ProgressSteps extends Component<Signature> {
  get steps() {
    const { progress } = this.args;
    const current = STEPS.findIndex((s) => s.key === progress.step);

    return STEPS.map((step, i) => {
      const failed = progress.failed && i === current + 1;

      return {
        label: step.label,
        note: this.noteFor(step.key, i, current),
        barClass: failed
          ? 'bg-danger'
          : i < current
            ? 'bg-success'
            : i === current
              ? 'bg-warning'
              : 'bg-secondary-subtle',
        labelClass: failed
          ? 'text-danger-emphasis fw-semibold'
          : i < current
            ? 'text-success-emphasis'
            : i === current
              ? 'text-warning-emphasis fw-semibold'
              : 'text-body-tertiary',
      };
    });
  }

  // Only say something where there is something to say — an empty note is
  // quieter than a row of em dashes.
  noteFor(key: Step, index: number, current: number): string | undefined {
    const { progress } = this.args;

    if (key === 'public' && progress.hold_date && index > current) {
      return `hold until ${progress.hold_date}`;
    }

    if (key === 'accession_issued' && progress.row_count > 0) {
      return `${progress.accessioned_count} of ${progress.row_count} issued`;
    }

    if (key === 'curating' && index === current) {
      return 'with a DDBJ curator';
    }

    return undefined;
  }

  <template>
    <h2 class="h6 text-uppercase text-body-secondary">Progress</h2>

    <ol class="list-unstyled d-flex gap-2 mb-4">
      {{#each this.steps as |step|}}
        <li class="flex-fill d-flex flex-column gap-2">
          <div class="progress-step-bar rounded-pill {{step.barClass}}"></div>
          <div class="small {{step.labelClass}}">{{step.label}}</div>
          {{#if step.note}}
            <div class="small text-body-tertiary">{{step.note}}</div>
          {{/if}}
        </li>
      {{/each}}
    </ol>
  </template>
}
