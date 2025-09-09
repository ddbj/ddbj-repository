# DDBJ Repository

``` mermaid
C4Container

Person(user, "User")

System_Ext(accounts, "accounts.ddbj.nig.ac.jp")
System_Ext(ddbj_validator, "DDBJ Validator")

Container_Boundary(repository, "DDBJ Repository") {
    ContainerDb(schema, "API Schema", "OpenAPI")
    Container(web, "Web UI", "Ember.js")

    Container_Boundary(api, "API") {
        Container(proxy, "Reverse Proxy", "Varnish")
        Container(app, "Application Server", "Puma (Rails)")
        ContainerQueue(worker, "Background Job Worker", "Solid Queue")
        Container_Ext(mb_tools, "ddbj/metabobank_tools")
        ContainerDb_Ext(object_storage, "Object Storage", "MinIO")
        ContainerDb_Ext(db, "Database", "PostgreSQL")
        Container_Ext(excel2xml, "ddbj/submission-excel2xml")
        Container(noodles-gff, "noodles_gff-rb")
    }
}

Rel(user, accounts, "Logs in to")
Rel(user, proxy, "Uses for accessing API")
Rel(user, web, "Accesses Web UI")

Rel(web, schema, "Uses")
Rel(web, proxy, "Uses for accessing API")

Rel(proxy, app, "Forwards requests to")
Rel(proxy, object_storage, "Forwards requests to")

Rel(app, accounts, "Requests authorization from")
Rel(app, schema, "Uses")
Rel(app, db, "Reads from and writes to")
Rel(app, object_storage, "Reads files from")

Rel(worker, object_storage, "Writes files to")
Rel(worker, db, "Reads from and writes to")
Rel(worker, ddbj_validator, "Validates BioProject/BioSample files using")
Rel(worker, mb_tools, "Validates MetaboBank files using")
Rel(worker, excel2xml, "Validates DRA files using")
Rel(worker, noodles-gff, "Validates GFF3 files using")
```
