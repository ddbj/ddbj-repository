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

  pruneIfWhole = () => {
    const boxes = this.boxes;

    if (boxes.length > 0 && boxes.every((box) => box.checked)) {
      boxes.forEach((box) => {
        box.disabled = true;
      });
    }
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
