import { Controller } from '@hotwired/stimulus';

const INTERVAL_MS = 3000;

export default class extends Controller {
  connect() {
    this.timer = setInterval(() => {
      Turbo.visit(location.href, { action: 'replace' });
    }, INTERVAL_MS);
  }

  disconnect() {
    clearInterval(this.timer);
  }
}
