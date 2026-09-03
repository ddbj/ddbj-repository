import type { components } from 'schema/openapi';

type SubmissionRequest = components['schemas']['SubmissionRequest'];
type SubmissionRequestSummary = components['schemas']['SubmissionRequestSummary'];

// The list row and the detail answer the same question from the same
// facts — the summary simply carries fewer of them. Typing the input as
// what both have in common is what keeps a row and the page it opens
// from ever disagreeing.
type StatefulRequest = SubmissionRequest | SubmissionRequestSummary;

export type Tone = 'action' | 'waiting' | 'done' | 'failed';

export interface RequestState {
  tone: Tone;
  // Short enough for a table cell: "Ready for you to submit".
  label: string;

  // The same fact about somebody else's submission. Every word on this
  // screen is written to the submitter, which reads as an instruction
  // when a colleague is the one looking — see `stateLabel`. Absent where
  // the label says nothing about who is being addressed.
  sharedLabel?: string;

  badge: string;
  heading: string;
  body: string;
}

// "Ready for you to submit" over a colleague's row is a lie about whose
// move it is.
export function stateLabel(request: StatefulRequest, { owned }: { owned: boolean }) {
  const state = requestState(request);

  return owned ? state.label : (state.sharedLabel ?? state.label);
}

const TONE_CLASSES: Record<Tone, { border: string; badge: string }> = {
  action: { border: 'border-warning-subtle bg-warning-subtle', badge: 'text-bg-warning' },
  waiting: { border: 'border-secondary-subtle bg-body-tertiary', badge: 'text-bg-secondary' },
  done: { border: 'border-success-subtle bg-success-subtle', badge: 'text-bg-success' },
  failed: { border: 'border-danger-subtle bg-danger-subtle', badge: 'text-bg-danger' },
};

export function toneClasses(tone: Tone) {
  return TONE_CLASSES[tone];
}

// The first question a submitter has is "is this on me, or am I waiting?"
// — and the raw status enum does not answer it. `waiting_application`
// and `applied` are both "nothing to do"; `ready_to_apply` and an unread
// curator question are both "your move", for completely different
// reasons. This maps the request onto that single question, in words.
//
// Ordered by urgency: a broken pipeline first, then a step only the
// submitter can take, then a curator's question, then the quiet states.
export function requestState(request: StatefulRequest): RequestState {
  // Checked first: whatever else is true of a request, the submitter has
  // said they are not taking it further, and every reading below would
  // ask them for something.
  //
  // Worded apart from `progress.closed` below on purpose. That one is the
  // record leaving the pipeline — a curator withdrew, canceled or
  // suppressed it. This one is the submitter putting their own attempt
  // down, and calling both "Closed" would leave no way to tell which
  // happened.
  if (request.closed_at) {
    return {
      tone: 'waiting',
      label: 'You closed this',
      sharedLabel: 'Closed by the submitter',
      badge: 'Closed by you',
      heading: 'You closed this request',
      body: 'It is kept, with its validation report and any messages, but it is no longer waiting on you. Reopen it if you want it back.',
    };
  }

  if (request.progress.failed) {
    return {
      tone: 'failed',
      label: 'Could not be processed',
      badge: 'Action needed',
      heading: 'This submission could not be processed',
      body:
        ('error_message' in request ? request.error_message : null) ??
        'Check the validation report below, correct the file and submit it again.',
    };
  }

  // Withdrawn / canceled / suppressed. Checked before the quiet states
  // below, which would otherwise tell the submitter a curator is reviewing
  // a record that has left the pipeline entirely.
  if (request.progress.closed) {
    return {
      tone: 'waiting',
      label: 'Closed',
      badge: 'Closed',
      heading: 'This submission is no longer in progress',
      body: 'It has been withdrawn, canceled or suppressed. Contact the DDBJ curator if that is unexpected.',
    };
  }

  if (request.processing) {
    return {
      tone: 'waiting',
      label: 'Being checked',
      badge: 'In progress',
      heading: 'We are checking your file',
      body: 'This page updates itself — nothing to do while it runs.',
    };
  }

  if (request.status === 'ready_to_apply') {
    // A check expires while its request stays `ready_to_apply`, so the
    // status alone would have this panel say "ready to submit" over a
    // page whose button is refusing. `sendable` is on the row as well as
    // on the page for exactly this line.
    if (!request.sendable) {
      return {
        tone: 'action',
        label: 'Needs checking again',
        sharedLabel: 'Waiting to be checked again',
        badge: 'Action needed',
        heading: 'The check on your file has expired',
        body: 'Nothing is wrong with the file. A submission is sent on the strength of a current check, so run it again and then send.',
      };
    }

    return {
      tone: 'action',
      label: 'Ready for you to submit',
      sharedLabel: 'Ready to submit',
      badge: 'Action needed',
      heading: 'Your file passed validation and is ready to submit',
      body: 'Review the validation report below, then press Send to DDBJ to hand it over.',
    };
  }

  if (request.unread_curator_message_count > 0) {
    const n = request.unread_curator_message_count;

    return {
      tone: 'action',
      label: n === 1 ? 'A curator has a question' : `A curator has ${n} questions`,
      badge: 'Action needed',
      heading: n === 1 ? 'A curator has a question' : `A curator has ${n} questions`,
      body:
        'Your submission has been accepted and is being curated — you do not need to resubmit the file. ' +
        'Reply in the thread below; accessions are issued once it is resolved.',
    };
  }

  switch (request.progress.step) {
    case 'public':
      return {
        tone: 'done',
        label: 'Public',
        badge: 'Released',
        heading: 'This submission is public',
        body: 'Nothing further is required.',
      };

    case 'accession_issued':
      return {
        tone: 'done',
        label: 'Accessions issued',
        badge: 'Accessions issued',
        heading: 'Accessions have been issued',
        body: request.progress.hold_date
          ? `The record stays private until ${request.progress.hold_date}.`
          : 'The record will be released once curation is complete.',
      };

    default:
      return {
        tone: 'waiting',
        label: 'With DDBJ',
        badge: 'With DDBJ',
        heading: 'A curator is reviewing your submission',
        body: 'Nothing is needed from you. We will email you if a curator has a question.',
      };
  }
}
