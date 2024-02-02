import Component from '@glimmer/component';
import { action } from '@ember/object';

import ENV from 'ddbj-repository/config/environment';

interface Signature {
  Args: {
    db?: string;
    dbChanged: (db?: string) => void;
    created?: string;
    createdChanged: (created?: string) => void;
  };
}

export default class ValidationsSearchFormComponent extends Component<Signature> {
  dbs = ENV.dbs;

  isDBSelected = (db: string) => this.selectedDBs.includes(db);

  get selectedDBs() {
    const { db } = this.args;

    return db?.split(',') || [];
  }

  @action
  toggleDB(e: Event) {
    const { checked, value } = e.target as HTMLInputElement;

    let db;

    if (checked) {
      db = [...this.selectedDBs, value].join(',');
    } else {
      db = this.selectedDBs.filter((db) => db !== value).join(',') || undefined;
    }

    this.args.dbChanged(db);
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ValidationsSearchForm: typeof ValidationsSearchFormComponent;
  }
}
