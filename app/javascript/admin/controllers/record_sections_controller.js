import { Controller } from '@hotwired/stimulus';

// Opens the section a link in the Carries row points at.
//
// The big sections start folded, and a fragment link lands on a closed
// one — the browser scrolls to a heading and the reader sees nothing new,
// which reads as a broken link rather than as a closed box. Browser search
// opens a closed <details> by itself; fragment navigation does not, and
// CSS cannot express it either (:target can style the element, not open
// it).
//
// The click is handled here rather than left to the browser because Turbo
// does not treat a same-page fragment as same-page: it fetches the URL and
// replaces the body. The section would open — on a freshly rendered
// page — but every other section the curator had opened by hand would
// close again, and a jump down the page would cost a round trip.
export default class extends Controller {
  connect() {
    this.reveal = this.reveal.bind(this);

    // A fragment typed or pasted into the address bar. Turbo intercepts
    // the links on this page, so this fires for nothing else.
    window.addEventListener('hashchange', this.reveal);
    this.reveal();
  }

  disconnect() {
    window.removeEventListener('hashchange', this.reveal);
  }

  // Bound to the Carries links, which point within this page.
  jump(event) {
    const target = this.#sectionFor(event.currentTarget.hash);

    if (!target) return;

    event.preventDefault();

    // replaceState rather than pushState: the fragment belongs in the
    // address bar so the section can be linked to, but a history entry per
    // glance at the table of contents turns Back into a chore. Turbo keeps
    // its restoration identifier in history.state, so carry it over.
    window.history.replaceState(window.history.state, '', event.currentTarget.hash);

    this.#open(target);
  }

  reveal() {
    const target = this.#sectionFor(window.location.hash);

    if (target) this.#open(target);
  }

  #sectionFor(hash) {
    if (!hash) return null;

    const target = document.getElementById(this.#idFrom(hash));

    return target && this.element.contains(target) ? target : null;
  }

  // The fragment comes from the address bar and need not be a valid
  // selector, nor validly escaped — `#50%` is a URIError, not a section.
  #idFrom(hash) {
    const raw = hash.slice(1);

    try {
      return decodeURIComponent(raw);
    } catch {
      return raw;
    }
  }

  #open(target) {
    target.closest('details')?.setAttribute('open', '');

    // Scroll after opening: on a fragment the browser has already scrolled
    // to a heading that was closed at the time, leaving the body it just
    // grew below the fold.
    target.scrollIntoView();
  }
}
