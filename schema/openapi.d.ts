/**
 * This file was auto-generated by openapi-typescript.
 * Do not make direct changes to the file.
 */


export interface paths {
  "/api-key": {
    /** @description Get login URL. */
    get: {
      responses: {
        /** @description Returns the login URL. Open this URL in your browser. */
        200: {
          content: {
            "application/json": {
              /** Format: uri */
              login_url: string;
            };
          };
        };
      };
    };
  };
  "/api-key/regenerate": {
    /** @description Re-generate API key. */
    post: {
      responses: {
        /** @description Returns a new API key. */
        200: {
          content: {
            "application/json": {
              api_key: string;
            };
          };
        };
        401: components["responses"]["Unauthorized"];
      };
    };
  };
  "/me": {
    /** @description Get your login ID. */
    get: {
      responses: {
        /** @description Returns the user's login ID. */
        200: {
          content: {
            "application/json": {
              uid: string;
              admin: boolean;
            };
          };
        };
        401: components["responses"]["Unauthorized"];
      };
    };
  };
  "/validations": {
    /** @description Get your validations. */
    get: {
      parameters: {
        query?: {
          /** @description The page number to return. The default is 1. */
          page?: number;
          /**
           * @description If true, return all validations. If false, return only your validations.
           * (Administrator only)
           */
          everyone?: boolean;
          /**
           * @description Return validations of the specified users.
           * (Administrator only)
           */
          uid?: string[];
          /** @description Return validations of the specified databases. */
          db?: ("BioProject" | "BioSample" | "Trad" | "DRA" | "GEA" | "MetaboBank" | "JVar" | "Trad2")[];
          created_at_after?: string;
          created_at_before?: string;
          progress?: ("waiting" | "running" | "finished" | "canceled")[];
          validity?: ("valid" | "invalid" | "error" | "null")[];
          submitted?: boolean;
        };
      };
      responses: {
        200: components["responses"]["Validations"];
        400: components["responses"]["BadRequest"];
        401: components["responses"]["Unauthorized"];
      };
    };
  };
  "/validations/via-file": {
    /** @description Validate submission files. */
    post: {
      requestBody: components["requestBodies"]["ViaFile"];
      responses: {
        /** @description The validation process initiated successfully. */
        201: {
          content: {
            "application/json": components["schemas"]["Validation"];
          };
        };
        400: components["responses"]["BadRequest"];
        401: components["responses"]["Unauthorized"];
        422: components["responses"]["UnprocessableEntity"];
      };
    };
  };
  "/validations/{id}": {
    /** @description Get the validation. */
    get: {
      parameters: {
        path: {
          /** @example 42 */
          id: number;
        };
      };
      responses: {
        /** @description Return the validation. */
        200: {
          content: {
            "application/json": components["schemas"]["Validation"];
          };
        };
        401: components["responses"]["Unauthorized"];
        404: components["responses"]["NotFound"];
      };
    };
    /** @description Cancel the validation. */
    delete: {
      parameters: {
        path: {
          /** @example 42 */
          id: number;
        };
      };
      responses: {
        /** @description Validation canceled successfully. */
        200: {
          content: {
            "application/json": {
              message: string;
            };
          };
        };
        400: components["responses"]["BadRequest"];
        401: components["responses"]["Unauthorized"];
        404: components["responses"]["NotFound"];
        422: components["responses"]["UnprocessableEntity"];
      };
    };
  };
  "/validations/{id}/files/{path}": {
    /** @description Get the submission file content. */
    get: {
      parameters: {
        path: {
          id: number;
          /** @example dest/mybiosample.xml */
          path: string;
        };
      };
      responses: {
        /** @description Redirect to the file. */
        302: {
          content: never;
        };
        401: components["responses"]["Unauthorized"];
        404: components["responses"]["NotFound"];
      };
    };
  };
  "/submissions": {
    /** @description Get your submissions. */
    get: {
      parameters: {
        query?: {
          page?: number;
        };
      };
      responses: {
        /** @description Return your submissions. */
        200: {
          headers: {
            /** @description The GitHub-style pagination URLs. See [Using pagination in the REST API - GitHub Docs](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api?apiVersion=2022-11-28) for details. */
            Link?: string;
          };
          content: {
            "application/json": components["schemas"]["Submission"][];
          };
        };
        400: components["responses"]["BadRequest"];
        401: components["responses"]["Unauthorized"];
        404: components["responses"]["NotFound"];
      };
    };
    /** @description Submit the validation. */
    post: {
      requestBody?: {
        content: {
          "application/json": {
            validation_id: number;
          };
        };
      };
      responses: {
        /** @description Submitted successfully. */
        201: {
          content: {
            "application/json": components["schemas"]["Submission"];
          };
        };
        400: components["responses"]["BadRequest"];
        401: components["responses"]["Unauthorized"];
        422: components["responses"]["UnprocessableEntity"];
      };
    };
  };
  "/submissions/{id}": {
    /** @description Get the submission. */
    get: {
      parameters: {
        path: {
          /** @example X-42 */
          id: string;
        };
      };
      responses: {
        /** @description Return the submission. */
        200: {
          content: {
            "application/json": components["schemas"]["Submission"];
          };
        };
        401: components["responses"]["Unauthorized"];
        404: components["responses"]["NotFound"];
      };
    };
  };
}

export type webhooks = Record<string, never>;

export interface components {
  schemas: {
    Validation: {
      id: number;
      /** Format: uri */
      url: string;
      user: {
        uid: string;
      };
      /** @enum {string} */
      db: "BioProject" | "BioSample" | "Trad" | "DRA" | "GEA" | "MetaboBank" | "JVar" | "Trad2";
      /** Format: date-time */
      created_at: string;
      /** Format: date-time */
      started_at: string | null;
      /** Format: date-time */
      finished_at: string | null;
      /** @enum {string} */
      progress: "waiting" | "running" | "finished" | "canceled";
      /** @enum {string|null} */
      validity: "valid" | "invalid" | "error" | null;
      objects: components["schemas"]["Objects"];
      results: components["schemas"]["ValidationResult"][];
      submission: {
        id: string;
        /** Format: uri */
        url: string;
      } | null;
    };
    Submission: {
      id: string;
      /** Format: date-time */
      created_at: string;
      validation: components["schemas"]["Validation"];
    };
    Objects: ({
        /** @enum {string} */
        id: "BioProject" | "BioSample" | "Sequence" | "Annotation" | "Submission" | "Experiment" | "Run" | "RunFile" | "Analysis" | "AnalysisFile" | "IDF" | "SDRF" | "ADF" | "RawDataFile" | "ProcessedDataFile" | "MAF" | "Excel" | "VariantCallFile" | "Metadata";
        files: {
            path: string;
            /** Format: uri */
            url: string;
          }[];
      })[];
    ValidationResult: {
      /** @enum {string} */
      object_id: "_base" | "BioProject" | "BioSample" | "Sequence" | "Annotation" | "Submission" | "Experiment" | "Run" | "RunFile" | "Analysis" | "AnalysisFile" | "IDF" | "SDRF" | "ADF" | "RawDataFile" | "ProcessedDataFile" | "MAF" | "Excel" | "VariantCallFile" | "Metadata";
      /** @enum {string|null} */
      validity: "valid" | "invalid" | "error" | null;
      details: Record<string, never> | null;
      file: {
        path: string;
        /** Format: uri */
        url: string;
      } | null;
    };
    /** Format: binary */
    File: string;
    /**
     * @description Path of the file on the NIG supercomputer, relative to the home directory of the authorised user.
     *
     * Note: If both file and path are specified, the file takes precedence.
     */
    Path: string;
    /** @description Destination of the file to be submitted. */
    Destination: string;
    Error: {
      error: string;
    };
    BioProjectViaFile: {
      /** @enum {string} */
      db: "BioProject";
      BioProject: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
    };
    BioSampleViaFile: {
      /** @enum {string} */
      db: "BioSample";
      BioSample: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
    };
    TradViaFile: {
      /** @enum {string} */
      db: "Trad";
      Sequence: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      Annotation: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
    };
    DRAViaFile: {
      /** @enum {string} */
      db: "DRA";
      Submission: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      Experiment: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      Run: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      RunFile: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      Analysis?: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      AnalysisFile?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
    };
    GEAViaFile: {
      /** @enum {string} */
      db: "GEA";
      IDF: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      SDRF: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      ADF?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      RawDataFile?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      ProcessedDataFile?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
    };
    MetaboBankViaFile: {
      /** @enum {string} */
      db: "MetaboBank";
      IDF: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      SDRF: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      MAF?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      RawDataFile?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      ProcessedDataFile?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      BioSample?: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
    };
    JVarViaFile: {
      /** @enum {string} */
      db: "JVar";
      Excel: {
        file?: components["schemas"]["File"];
        path?: components["schemas"]["Path"];
        destination?: components["schemas"]["Destination"];
      };
      VariantCallFile?: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
    };
    Trad2ViaFile: {
      /** @enum {string} */
      db: "Trad2";
      Sequence: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      Annotation: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
      Metadata: {
          file?: components["schemas"]["File"];
          path?: components["schemas"]["Path"];
          destination?: components["schemas"]["Destination"];
        }[];
    };
  };
  responses: {
    /** @description Return your validations. */
    Validations: {
      headers: {
        /** @description GitHub-style pagination URLs. See [Using pagination in the REST API - GitHub Docs](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api?apiVersion=2022-11-28) for details. */
        Link?: string;
      };
      content: {
        "application/json": components["schemas"]["Validation"][];
      };
    };
    /** @description Unexpected parameter specified. */
    BadRequest: {
      content: {
        "application/json": components["schemas"]["Error"];
      };
    };
    /** @description Not authenticated. */
    Unauthorized: {
      content: {
        "application/json": components["schemas"]["Error"];
      };
    };
    /** @description Does not have access rights to the resource. */
    Forbidden: {
      content: {
        "application/json": components["schemas"]["Error"];
      };
    };
    /** @description The requested resource could not be found. */
    NotFound: {
      content: {
        "application/json": components["schemas"]["Error"];
      };
    };
    /** @description Invalid parameter or payload was specified. */
    UnprocessableEntity: {
      content: {
        "application/json": components["schemas"]["Error"];
      };
    };
  };
  parameters: never;
  requestBodies: {
    ViaFile?: {
      content: {
        "multipart/form-data": components["schemas"]["BioProjectViaFile"] | components["schemas"]["BioSampleViaFile"] | components["schemas"]["TradViaFile"] | components["schemas"]["DRAViaFile"] | components["schemas"]["GEAViaFile"] | components["schemas"]["MetaboBankViaFile"] | components["schemas"]["JVarViaFile"] | components["schemas"]["Trad2ViaFile"];
      };
    };
  };
  headers: never;
  pathItems: never;
}

export type $defs = Record<string, never>;

export type external = Record<string, never>;

export type operations = Record<string, never>;
