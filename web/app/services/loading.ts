import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';

export default class extends Service {
  @tracked isLoading = false;

  start() {
    this.isLoading = true;
  }

  stop() {
    this.isLoading = false;
  }
}
