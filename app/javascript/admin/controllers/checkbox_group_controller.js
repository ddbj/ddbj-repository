import { Controller } from '@hotwired/stimulus';

// Select-all / deselect-all for one multi-select filter facet. Wraps a
// row of checkboxes; the two buttons flip every checkbox inside this
// controller's element.
//
// It also keeps a facet that constrains nothing out of the URL. Every box
// is checked when the param is absent, so without this, pressing Search
// posts `db[]=st26&db[]=bioproject&db[]=biosample` — which the ledger
// reads as no constraint, and which then has to be un-read by everything
// that describes the screen. Ticking everything and pressing Clear now
// arrive at the same address, which is what they always meant.
//
// Disabled rather than unchecked: unchecking would flicker the boxes off
// in front of the curator on the way out. Both are equivalent to the
// server, which treats an empty selection as no constraint too.
export default class extends Controller {
  connect() {
    this.form = this.element.closest('form');
    this.form?.addEventListener('submit', this.pruneIfWhole);
  }

  disconnect() {
    this.form?.removeEventListener('submit', this.pruneIfWhole);
  }

  // Disabled only for as long as it takes the form to be read. `disabled`
  // reflects to the attribute, and Turbo snapshots the page on the way
  // out — so left set, a Back button would restore a cached page with
  // every facet greyed out and unclickable until a hard reload. A
  // submission that never completes (network gone, load stopped) would
  // strand them the same way.
  //
  // The restore is a task later, which is after both Turbo and the
  // browser have serialised the form: they read it synchronously while
  // the submit event is still being dispatched.
  pruneIfWhole = () => {
    const boxes = this.boxes;

    if (boxes.length === 0 || !boxes.every((box) => box.checked)) return;

    boxes.forEach((box) => {
      box.disabled = true;
    });

    setTimeout(() => {
      boxes.forEach((box) => {
        box.disabled = false;
      });
    }, 0);
  };

  get boxes() {
    return [...this.element.querySelectorAll('input[type="checkbox"]')];
  }

  selectAll() {
    this.setAll(true);
  }

  deselectAll() {
    this.setAll(false);
  }

  setAll(checked) {
    this.element.querySelectorAll('input[type="checkbox"]').forEach((box) => {
      box.checked = checked;
    });
  }
}
