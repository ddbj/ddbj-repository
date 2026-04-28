import Route from '@ember/routing/route';

export default class extends Route {
  model({ db }: { db: string }) {
    return { db };
  }
}
