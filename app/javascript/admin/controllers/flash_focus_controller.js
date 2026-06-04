import { Controller } from '@hotwired/stimulus';

// Scroll the host flash banner into view when it lands on the page.
//
// The admin layout uses `<meta name="turbo-refresh-method" content="morph">`
// + `<meta name="turbo-refresh-scroll" content="preserve">`, which means
// after a curator-edit form submit + redirect, the new flash banner
// renders at the top of the page but the curator is still scrolled
// down to wherever the form was. Without this controller the success
// notice never reaches the eye. The controller is attached per-flash
// in admin.html.erb so it only fires when a flash actually rendered.
export default class extends Controller {
  connect() {
    // The flash is in the DOM at the top of <main>. If the curator is
    // already at or above it (initial page load with a flash, or rare
    // scroll-into-view-via-anchor case), this scroll is a no-op.
    this.element.scrollIntoView({ block: 'start', behavior: 'smooth' });
  }
}
