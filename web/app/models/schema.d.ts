export interface DBSchema {
  id: string;
  objects: ObjSchema[];
}

export interface ObjSchema {
  id: string;
  required: boolean;
  multiple: boolean;
}
