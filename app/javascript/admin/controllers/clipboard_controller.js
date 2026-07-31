import { Controller } from '@hotwired/stimulus';

// Copy a block of text for pasting into a support request.
//
// The screen it serves used to send curators to Mission Control for the
// detail, which is a developer surface — the information they need to
// forward is a few lines, so the screen hands it over directly instead.
export default class extends Controller {
  static values = { text: String, label: String };

  copy() {
    // Restored on the next render; a button that stays "Copied" is
    // lying by the time the curator looks back at it.
    navigator.clipboard
      .writeText(this.textValue)
      .then(() => this.#flash('Copied'))
      .catch(() => this.#flash('Copy failed — select the text above'));
  }

  #flash(message) {
    if (!this.hasLabelValue) this.labelValue = this.element.textContent;

    this.element.textContent = message;

    setTimeout(() => {
      this.element.textContent = this.labelValue;
    }, 2000);
  }
}
