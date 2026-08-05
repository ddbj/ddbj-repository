import { Controller } from '@hotwired/stimulus';

// Locks a button until its phrase has been typed out.
//
// Reserved for the one scope that cannot be taken back by pressing it
// again — regenerating every flatfile in the database. A dialog anyone
// can dismiss with the Return key is not a decision, and the cost of
// typing four letters is the only part of this screen that scales with
// what is at stake.
//
// The server refuses the same request without the phrase, so this is a
// speed bump rather than the rule.
export default class extends Controller {
  static targets = ['input', 'submit'];
  static values = { phrase: String };

  connect() {
    this.check();
  }

  check() {
    const typed = this.inputTarget.value.trim().toLowerCase();

    this.submitTarget.disabled = typed !== this.phraseValue.toLowerCase();
  }
}
