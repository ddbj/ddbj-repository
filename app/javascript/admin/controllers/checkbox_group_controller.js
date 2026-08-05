import { Controller } from '@hotwired/stimulus';

// Select-all / deselect-all for one multi-select filter facet. Wraps a
// row of checkboxes; the two buttons flip every checkbox inside this
// controller's element. Purely client-side — the surrounding GET form is
// submitted separately with whatever ends up checked.
export default class extends Controller {
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
