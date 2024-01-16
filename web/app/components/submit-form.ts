import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { task } from 'ember-concurrency';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ErrorModalService from 'ddbj-repository/services/error-modal';
import type Router from '@ember/routing/router';

type Signature = {
  Args: {
    db: DB;
  };
};

export default class SubmitFormConponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare router: Router;

  submit = task({ drop: true }, async (e: Event) => {
    const { db } = this.args;

    e.preventDefault();

    const res = await fetch(`${ENV.apiURL}/validations/via-file`, {
      method: 'POST',
      headers: this.currentUser.authorizationHeader,
      body: jsonToFormData(db.toJSON()),
    });

    if (!res.ok) {
      this.errorModal.show(new Error(res.statusText));
    }

    const { request } = await res.json();

    this.router.transitionTo('validations.show', request.id);
  });
}

export class DB {
  schema: DBSchema;
  objs: Obj[];

  constructor(schema: DBSchema) {
    this.schema = schema;
    this.objs = this.schema.objects.map((obj) => new Obj(this, obj));
  }

  toJSON() {
    return this.objs.reduce(
      (acc, obj) => ({
        ...acc,
        [obj.schema.id]: obj.toJSON(),
      }),
      { db: this.schema.id },
    );
  }
}

export class Obj {
  db: DB;
  schema: ObjSchema;

  @tracked sourceType: 'file' | 'path' = 'file';
  @tracked sources: Source[];

  constructor(db: DB, schema: ObjSchema) {
    const { optional, multiple } = schema;

    this.db = db;
    this.schema = schema;
    this.sources = optional && multiple ? [] : [new Source(this)];
  }

  get canRemoveSource() {
    return this.schema.optional || this.sources.length > 1;
  }

  @action
  addSource() {
    this.sources = [...this.sources, new Source(this)];
  }

  @action
  removeSource(source: Source) {
    this.sources = this.sources.filter((_source) => _source !== source);
  }

  toJSON() {
    const { schema, sources } = this;

    return schema.multiple ? sources.map((source) => source.toJSON()) : sources[0]!.toJSON();
  }
}

export class Source {
  obj: Obj;

  @tracked file?: File;
  @tracked path = '';
  @tracked destination = '';

  constructor(obj: Obj) {
    this.obj = obj;
  }

  get required() {
    const { optional, multiple } = this.obj.schema;

    return !optional || multiple;
  }

  toJSON() {
    const { file, path, obj, destination } = this;

    if (!file && !path) return undefined;

    switch (obj.sourceType) {
      case 'file':
        return { file, destination };
      case 'path':
        return { path, destination };
    }
  }
}

function jsonToFormData(obj: object, key?: string, formData = new FormData()) {
  if (Array.isArray(obj)) {
    for (const v of obj) {
      jsonToFormData(v, `${key}[]`, formData);
    }
  } else if (Object.prototype.toString.call(obj) === '[object Object]') {
    for (const [k, v] of Object.entries(obj)) {
      jsonToFormData(v, key ? `${key}[${k}]` : k, formData);
    }
  } else {
    if (!key) throw new Error('key is empty');

    if (obj !== undefined) {
      formData.append(key, obj instanceof Blob ? obj : obj.toString());
    }
  }

  return formData;
}
