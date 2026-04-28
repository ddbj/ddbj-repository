import Route from '@ember/routing/route';

export default class extends Route {
  model() {
    const { db } = this.paramsFor('db') as { db: string };

    return { db };
  }
}
