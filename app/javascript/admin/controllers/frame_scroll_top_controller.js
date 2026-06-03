import { Controller } from '@hotwired/stimulus';

// Scroll the host <turbo-frame>'s top edge into view after frame loads.
//
// Skips when the frame is already at or below the viewport top — that
// covers both the initial page load (user is above the frame, no scroll
// needed) and the case where the user happens to already be looking at
// the start of the table. Acts only when the user has scrolled past the
// frame top (typical "click pagy nav, see next page from the top"
// flow).
export default class extends Controller {
  connect() {
    this.handler = this.scrollIfBelowViewport.bind(this);
    this.element.addEventListener('turbo:frame-load', this.handler);
  }

  disconnect() {
    this.element.removeEventListener('turbo:frame-load', this.handler);
  }

  scrollIfBelowViewport() {
    if (this.element.getBoundingClientRect().top < 0) {
      this.element.scrollIntoView({ block: 'start', behavior: 'smooth' });
    }
  }
}
