import Modifier from 'ember-modifier';
import { registerDestructor } from '@ember/destroyable';
import { service } from '@ember/service';

import type RouterService from '@ember/routing/router-service';

export default class AutoRefreshModifier extends Modifier {
  @service declare router: RouterService;

  timer: number | null = null;
  interval: number | null = null;

  modify(_el: Element, _positional: [], {while: _while, interval}: {while: boolean; interval: number}) {
    registerDestructor(this, stopRefreshing);

    if (!_while) {
      stopRefreshing(this);
      return;
    }

    if (this.timer && this.interval === interval) { return; }

    stopRefreshing(this);

    this.interval = interval;

    this.timer = setInterval(() => {
      this.router.refresh();
    }, interval);
  }
}

function stopRefreshing(instance: AutoRefreshModifier) {
  const { timer } = instance;

  if (!timer) { return; }

  clearInterval(timer);
  instance.timer = null;
}
