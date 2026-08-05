import Component from '@glimmer/component';

interface Signature {
  Args: {
    current: number;
  };
}

// Where you are in making a submission, as opposed to where the
// submission has got to once it exists — that is ProgressSteps, and the
// two never appear together.
//
// The middle step is deliberately vague about how the data gets made.
// That is expected to differ by database and to be replaced later
// (handing off to a per-database service, an editor in the page); the
// steps either side of it — pick a database, check it, send it — do not
// change when it is. Calling it "Your data" rather than "Upload" is what
// keeps that true.
const STEPS = ['Database', 'Your data', 'Check', 'Send to DDBJ'];

export default class SubmissionSteps extends Component<Signature> {
  get steps() {
    return STEPS.map((label, index) => {
      const position = index + 1;

      return {
        label,
        position,
        done: position < this.args.current,
        here: position === this.args.current,
      };
    });
  }

  <template>
    <ol class="list-unstyled d-flex align-items-center gap-2 flex-wrap mb-4" data-test-submission-steps>
      {{#each this.steps as |step|}}
        <li
          class="d-flex align-items-center gap-1 {{if step.here 'fw-semibold' 'text-body-secondary'}}"
          aria-current={{if step.here "step"}}
          data-test-step={{step.position}}
        >
          <span
            class="badge rounded-pill
              {{if step.done 'text-bg-success' (if step.here 'text-bg-primary' 'text-bg-light border')}}"
          >
            {{if step.done "✓" step.position}}
          </span>

          {{step.label}}
        </li>
      {{/each}}
    </ol>
  </template>
}
