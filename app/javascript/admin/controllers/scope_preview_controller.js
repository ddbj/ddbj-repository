import { Controller } from '@hotwired/stimulus';

// Keeps the summary beside a form in step with the form.
//
// The count in it is a question only the server can answer — "three
// accession numbers" is not three submissions until the database says so
// — and a summary that lags the fields is worse than none, because its
// whole job is to be checked against what was typed.
const DEBOUNCE_MS = 300;

export default class extends Controller {
  static values = { url: String };

  update() {
    clearTimeout(this.timer);

    this.timer = setTimeout(() => this.refresh(), DEBOUNCE_MS);
  }

  refresh() {
    const frame = this.element.querySelector('turbo-frame');
    if (!frame) return;

    // Read from the form itself rather than from tracked fields: adding
    // an option to the form should not also mean remembering to add it
    // here, which is how a summary starts quietly ignoring one.
    const params = new URLSearchParams(new FormData(this.element));

    // The token is the form's, not the summary's, and it is a POST-only
    // concern — sending it on a GET only widens what the URL carries.
    params.delete('authenticity_token');

    frame.src = `${this.urlValue}?${params}`;
  }

  disconnect() {
    clearTimeout(this.timer);
  }
}
