import { Controller } from '@hotwired/stimulus';

// Keeps the summary beside a form in step with the form.
//
// The count in it is a question only the server can answer — "three
// accession numbers" is not three submissions until the database says so
// — and a summary that lags the fields is worse than none, because its
// whole job is to be checked against what was typed.
const DEBOUNCE_MS = 300;

export default class extends Controller {
  static targets = ['panel', 'setDate'];
  static values = { url: String };

  update() {
    clearTimeout(this.timer);

    this.timer = setTimeout(() => this.refresh(), DEBOUNCE_MS);
  }

  // Typing a date is choosing to set one. Without this the field can be
  // filled in under an unselected radio, and the run silently keeps the
  // existing dates.
  dateEntered(event) {
    if (event.target.value) this.setDateTarget.checked = true;

    this.update();
  }

  async refresh() {
    // POST, because the form carries the accession list: a bulk paste is
    // thousands of numbers, and a query string that long is refused by
    // the proxy before it reaches the app.
    //
    // Read from the form itself rather than from tracked fields: adding
    // an option to the form should not also mean remembering to add it
    // here, which is how a summary starts quietly ignoring one.
    this.pending?.abort();
    this.pending = new AbortController();

    const body = new FormData(this.element);

    // The form's own token is scoped to the form's action, so posting it
    // to the preview would be rejected as forged. The session-wide token
    // from the page head is what a request outside a form uses.
    body.delete('authenticity_token');

    try {
      const response = await fetch(this.urlValue, {
        method: 'POST',
        body,
        headers: {
          Accept: 'text/html',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content,
        },
        signal: this.pending.signal,
      });

      if (response.ok) this.panelTarget.innerHTML = await response.text();
    } catch (error) {
      // An aborted request is this controller superseding itself, not a
      // failure. Anything else leaves the last good summary up rather
      // than blanking the panel the button lives in.
      if (error.name !== 'AbortError') throw error;
    }
  }

  disconnect() {
    clearTimeout(this.timer);
    this.pending?.abort();
  }
}
