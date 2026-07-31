import { Controller } from '@hotwired/stimulus';

// Keeps the release-notice preview in step with the fields being edited.
//
// Without this the panel shows the *saved* template, so a curator checks
// their edit against the text it is replacing — which is the one mistake
// the preview exists to prevent. The accession block in the middle is
// server-rendered from a real candidate and never changes as you type, so
// only the prose around it is updated here.
export default class extends Controller {
  static targets = ['subject', 'body', 'subjectPreview', 'before', 'after'];

  static values = { placeholder: String };

  connect() {
    this.render();
  }

  render() {
    this.subjectPreviewTarget.textContent = this.subjectTarget.value;

    // Split on the same placeholder the server splits on. A body that has
    // lost it is invalid and will be refused on save; until then, showing
    // the whole thing before an empty tail is the honest rendering.
    const [before, after] = this.bodyTarget.value.split(this.placeholderValue, 2);

    this.beforeTarget.textContent = (before ?? '').trimEnd();
    this.afterTarget.textContent = (after ?? '').trimStart();
  }
}
