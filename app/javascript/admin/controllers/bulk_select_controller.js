import { Controller } from '@hotwired/stimulus';

// Bulk-row selection on the admin submissions index.
//
// - `toggle` target: a header checkbox that flips all row checkboxes.
// - `row` target: per-submission checkboxes.
// - `counter` target: a badge that mirrors the current selected count.
//
// All wiring is event-driven; no implicit Stimulus lifecycle hooks beyond
// initial count rendering on connect. The Bootstrap `data-turbo-confirm`
// on the Apply button handles the destructive-action prompt separately.
export default class extends Controller {
  static targets = ['toggle', 'row', 'counter'];

  connect() {
    this.refreshCounter();
  }

  toggleTargetConnected() {
    this.toggleTarget.addEventListener('change', () => this.applyToAll());
  }

  rowTargetConnected(el) {
    el.addEventListener('change', () => this.refreshCounter());
  }

  applyToAll() {
    this.rowTargets.forEach((cb) => { cb.checked = this.toggleTarget.checked; });
    this.refreshCounter();
  }

  refreshCounter() {
    if (!this.hasCounterTarget) return;
    const n = this.rowTargets.filter((cb) => cb.checked).length;
    this.counterTarget.textContent = String(n);
  }
}
