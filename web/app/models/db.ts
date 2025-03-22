import Obj from 'repository/models/obj';

import type { DBSchema } from 'schema/db';

export default class DB {
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
