# DDBJ Repository

A submission management system for [DDBJ (DNA Data Bank of Japan)](https://www.ddbj.nig.ac.jp/). Users submit sequence data in ST.26 XML format, which is validated, assigned accession numbers, and converted to DDBJ flatfiles.

## Architecture

```mermaid
C4Container

Person(user, "User")

System_Ext(accounts, "accounts.ddbj.nig.ac.jp")
System_Ext(ddbj_validator, "DDBJ Validator")

Container_Boundary(repository, "DDBJ Repository") {
    ContainerDb(schema, "API Schema", "OpenAPI")
    Container(web, "Web UI", "Ember.js")

    Container_Boundary(api, "API") {
        Container(proxy, "Reverse Proxy", "Nginx")
        Container(app, "Application Server", "Puma (Rails)")
        ContainerQueue(worker, "Background Job Worker", "Solid Queue")
        Container_Ext(mb_tools, "ddbj/metabobank_tools")
        ContainerDb_Ext(object_storage, "Object Storage", "SeaweedFS")
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

## Database Schema

```mermaid
erDiagram
    users {
        bigint id PK
        string uid UK "DDBJ Account ID"
        string api_key UK
        boolean admin "default: false"
        datetime created_at
        datetime updated_at
    }

    submissions {
        bigint id PK
        datetime created_at
        datetime updated_at
    }

    submission_requests {
        bigint id PK
        bigint user_id FK
        bigint submission_id FK "nullable"
        integer status "enum: waiting_validation..no_change"
        string error_message "nullable"
        datetime created_at
        datetime updated_at
    }

    submission_updates {
        bigint id PK
        bigint submission_id FK
        integer status "enum: waiting_validation..no_change"
        string error_message "nullable"
        string diff "nullable"
        datetime created_at
        datetime updated_at
    }

    accessions {
        bigint id PK
        bigint submission_id FK
        string number UK "e.g. LC000001"
        string entry_id
        integer version "default: 1"
        datetime last_updated_at
        datetime created_at
        datetime updated_at
    }

    validations {
        bigint id PK
        string subject_type "SubmissionRequest or SubmissionUpdate"
        bigint subject_id
        string progress "enum: running, finished, canceled"
        jsonb raw_result "nullable"
        datetime finished_at "nullable"
        datetime created_at
        datetime updated_at
    }

    validation_details {
        bigint id PK
        bigint validation_id FK
        string code
        string severity "enum: warning, error"
        string entry_id "nullable"
        string message
        datetime created_at
        datetime updated_at
    }

    sequences {
        bigint id PK
        string scope UK "accession number scope"
        string prefix
        bigint next "default: 1"
        datetime created_at
        datetime updated_at
    }

    users ||--o{ submission_requests : "has many"
    submission_requests |o--o| submissions : "creates"
    submissions ||--o{ submission_updates : "has many"
    submissions ||--o{ accessions : "has many"
    submission_requests ||--o| validations : "has one (polymorphic)"
    submission_updates ||--o| validations : "has one (polymorphic)"
    validations ||--o{ validation_details : "has many"
```

## Tech Stack

- **Backend:** Ruby on Rails, Puma, Solid Queue
- **Frontend:** Ember.js (Octane), TypeScript, Vite
- **Database:** PostgreSQL
- **Object Storage:** SeaweedFS (S3-compatible)
- **Deployment:** Kamal
- **API Schema:** OpenAPI

## Development

### Prerequisites

- Ruby (see `.ruby-version`)
- Node.js + pnpm
- PostgreSQL
- SeaweedFS

### Setup

```sh
bin/setup
```

### Running

```sh
bin/dev
```

### Deployment

```sh
bin/kamal deploy -d staging
bin/kamal deploy -d production
```
