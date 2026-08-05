import { Controller } from '@hotwired/stimulus';

// Scroll the host flash banner into view whenever a new flash lands on
// the page.
//
// The admin layout uses `<meta name="turbo-refresh-method" content="morph">`
// + `<meta name="turbo-refresh-scroll" content="preserve">`, which means
// after a curator-edit form submit + redirect, the new flash banner
// renders at the top of the page but the curator is still scrolled
// down to wherever the form was. Without this controller the success
// notice never reaches the eye.
//
// Why a value-change callback instead of `connect()`: Turbo's morph
// PRESERVES the existing `.alert` element across renders when its
// shape is similar; only the text inside changes. Stimulus's
// `connect()` fires once on first mount and not again, so a second
// save would update the message but not re-scroll. Token-value
// callbacks fire on initial connect AND whenever the value changes
// (morph updates the attribute → callback fires). The layout
// re-emits a random token per render so each new flash is a value
// change.
export default class extends Controller {
  static values = { token: String };

  tokenValueChanged() {
    this.element.scrollIntoView({ block: 'start', behavior: 'smooth' });
  }
}
