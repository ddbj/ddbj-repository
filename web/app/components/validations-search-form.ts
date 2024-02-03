import Component from '@glimmer/component';
import { action } from '@ember/object';

import ENV from 'ddbj-repository/config/environment';

const progresses = ['waiting', 'running', 'finished', 'canceled'] as const;

interface Signature {
  Element: HTMLDListElement;

  Args: {
    db?: string;
    dbChanged: (db?: string) => void;
    created?: string;
    createdChanged: (created?: string) => void;
    progress?: string;
    progressChanged: (progress?: string) => void;
  };
}

export default class ValidationsSearchFormComponent extends Component<Signature> {
  dbs = ENV.dbs.map((db) => db.id);

  get selectedDBs() {
    const { db } = this.args;

    return db === undefined ? this.dbs : db.split(',');
  }

  isDBSelected = (db: (typeof this.dbs)[number]) => this.selectedDBs.includes(db);

  @action
  toggleDB(e: Event) {
    const { checked, value } = e.target as HTMLInputElement;

    let db;

    if (checked) {
      const dbs = [...this.selectedDBs, value];

      db = dbs.length === this.dbs.length ? undefined : dbs.join(',');
    } else {
      db = this.selectedDBs.filter((db) => db !== value).join(',');
    }

    this.args.dbChanged(db);
  }

  get selectedProgresses() {
    const { progress } = this.args;

    return progress === undefined ? progresses : progress.split(',');
  }

  isProgressSelected = (progress: (typeof progresses)[number]) => this.selectedProgresses.includes(progress);

  @action
  toggleProgress(e: Event) {
    const { checked, value } = e.target as HTMLInputElement;

    let progress;

    if (checked) {
      const _progresses = [...this.selectedProgresses, value];

      progress = _progresses.length === progresses.length ? undefined : _progresses.join(',');
    } else {
      progress = this.selectedProgresses.filter((progress) => progress !== value).join(',');
    }

    this.args.progressChanged(progress);
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ValidationsSearchForm: typeof ValidationsSearchFormComponent;
  }
}
