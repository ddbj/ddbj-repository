export interface DBSchema {
    id:        string;
    validator: string;
    objects:   ObjSchema[];
}

export interface ObjSchema {
    id:        string;
    ext:       string;
    required?: boolean;
    multiple?: boolean;
}
