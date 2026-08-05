import { Controller } from '@hotwired/stimulus';

// A confirmation that opens where you are.
//
// The content is fetched into the turbo-frame inside, so the three Issue
// buttons open one server-rendered dialog rather than each page carrying
// its own copy of it — and pressing Cancel costs nothing, because the
// page behind never went away.
//
// Native <dialog>: Esc, the backdrop and the focus trap come free, which
// is the whole reason not to reach for Bootstrap's modal here. Its own
// `close` event is not used — the frame's lifecycle is what this tracks,
// and hanging cleanup off `close` made it depend on an event that does
// not reach us in every browser.
export default class extends Controller {
  static targets = ['frame'];

  connect() {
    this.frameTarget.addEventListener('turbo:before-fetch-request', this.clear);
    this.frameTarget.addEventListener('turbo:frame-load', this.open);
  }

  disconnect() {
    this.frameTarget.removeEventListener('turbo:before-fetch-request', this.clear);
    this.frameTarget.removeEventListener('turbo:frame-load', this.open);
  }

  // Emptied the moment a new confirmation starts loading. Otherwise the
  // previous one stays in the frame, and on a slow link the dialog opens
  // showing another request's count — the one thing a screen that exists
  // to state the count must never do.
  clear = (event) => {
    // Only the frame's own fetch. The event bubbles, and the confirmation
    // form inside targets _top — so submitting it used to empty the
    // dialog the curator is still looking at, leaving a blank box for the
    // length of the POST and its redirect.
    if (event.target !== this.frameTarget) return;

    this.frameTarget.innerHTML = '';
  };

  open = () => {
    if (!this.element.open) this.element.showModal();
  };

  // Cancel. Without a dialog around it — a direct visit to the
  // confirmation URL — no controller is connected, the action does not
  // fire, and the link navigates as an ordinary link instead.
  cancel(event) {
    event.preventDefault();
    this.element.close();
  }
}
