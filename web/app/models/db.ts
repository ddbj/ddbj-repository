import Obj from 'repository/models/obj';
import schema from 'schema/db';

type Schema = (typeof schema)[number];

export const dbNames = schema.map(({ id }) => id);

export type DBName = (typeof dbNames)[number];

export default class DB {
  schema: Schema;
  objs: Obj[];

  constructor(schema: Schema) {
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
