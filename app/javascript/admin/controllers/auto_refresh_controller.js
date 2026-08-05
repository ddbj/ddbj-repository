import { Controller } from '@hotwired/stimulus';

const INTERVAL_MS = 3000;

// Refreshes the smallest thing that contains it.
//
// A whole-page visit is right for a screen that is only a progress
// report, and wrong for one where the progress sits beside a form
// somebody is filling in — three seconds is not long enough to type an
// accession number into a field that is about to be re-rendered. When
// the panel is inside a frame of its own, that frame is what reloads.
export default class extends Controller {
  connect() {
    this.frame = this.element.closest('turbo-frame');

    this.timer = setInterval(() => {
      if (this.frame?.src) {
        this.frame.reload();
      } else {
        Turbo.visit(location.href, { action: 'replace' });
      }
    }, INTERVAL_MS);
  }

  disconnect() {
    clearInterval(this.timer);
  }
}
