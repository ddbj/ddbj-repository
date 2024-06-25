export interface DBSchema {
    id:      string;
    objects: ObjSchema[];
}

export interface ObjSchema {
    id:        string;
    ext:       string;
    required?: boolean;
    multiple?: boolean;
}
