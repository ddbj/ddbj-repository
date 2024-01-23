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
            };
          };
        };
        401: components["responses"]["Unauthorized"];
      };
    };
  };
  "/validations/via-file": {
    /** @description Validate submission files. */
    post: {
      requestBody: components["requestBodies"]["ViaFile"];
      responses: {
        201: components["responses"]["CreateResponseCreated"];
        400: components["responses"]["CreateResponseBadRequest"];
        401: components["responses"]["Unauthorized"];
        422: components["responses"]["UnprocessableEntity"];
      };
    };
  };
  "/validations": {
    /** @description Get your validations. */
    get: {
      parameters: {
        query?: {
          page?: number;
        };
      };
      responses: {
        /** @description Return your validations. */
        200: {
          headers: {
            /** @description GitHub-style pagination URLs. See [Using pagination in the REST API - GitHub Docs](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api?apiVersion=2022-11-28) for details. */
            Link?: string;
          };
          content: {
            "application/json": components["schemas"]["Validation"][];
          };
        };
        400: components["responses"]["BadRequest"];
        401: components["responses"]["Unauthorized"];
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
        401: components["responses"]["Unauthorized"];
        /** @description Validation already canceled or finished. */
        409: {
          content: {
            "application/json": components["schemas"]["Error"];
          };
        };
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
        400: components["responses"]["CreateResponseBadRequest"];
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
      /** @enum {string} */
      db: "BioProject" | "BioSample" | "Trad" | "DRA" | "GEA" | "MetaboBank" | "JVar";
      /** Format: date-time */
      created_at: string;
      /** Format: date-time */
      finished_at: string | null;
      /** @enum {string} */
      progress: "waiting" | "processing" | "finished" | "canceled";
      /** @enum {string|null} */
      validity: "valid" | "invalid" | "error" | null;
      objects: components["schemas"]["Objects"];
      validation_reports: components["schemas"]["ValidationReport"][];
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
        id: "BioProject" | "BioSample" | "Sequence" | "Annotation" | "Submission" | "Experiment" | "Run" | "RunFile" | "Analysis" | "AnalysisFile" | "IDF" | "SDRF" | "ADF" | "RawDataFile" | "ProcessedDataFile" | "MAF" | "Excel" | "VariantCallFile";
        files: {
            path: string;
            /** Format: uri */
            url: string;
          }[];
      })[];
    ValidationReport: {
      /** @enum {string} */
      object_id: "_base" | "BioProject" | "BioSample" | "Sequence" | "Annotation" | "Submission" | "Experiment" | "Run" | "RunFile" | "Analysis" | "AnalysisFile" | "IDF" | "SDRF" | "ADF" | "RawDataFile" | "ProcessedDataFile" | "MAF" | "Excel" | "VariantCallFile";
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
    /** @description Path of the file on the NIG supercomputer, relative to the home directory of the authorised user. */
    Path: string;
    /** @description Destination of the file to be submitted. */
    Destination: string;
    Error: {
      error: string;
    };
    BioProjectViaFile: {
      /** @enum {string} */
      db?: "BioProject";
      "BioProject[file]"?: components["schemas"]["File"];
      "BioProject[path]"?: components["schemas"]["Path"];
      "BioProject[destination]"?: components["schemas"]["Destination"];
    };
    BioSampleViaFile: {
      /** @enum {string} */
      db?: "BioSample";
      "BioSample[file]"?: components["schemas"]["File"];
      "BioSample[path]"?: components["schemas"]["Path"];
      "BioSample[destination]"?: components["schemas"]["Destination"];
    };
    TradViaFile: {
      /** @enum {string} */
      db?: "Trad";
      "Sequence[][file]"?: components["schemas"]["File"][];
      "Sequence[][path]"?: components["schemas"]["Path"][];
      "Sequence[][destination]"?: components["schemas"]["Destination"][];
      "Annotation[][file]"?: components["schemas"]["File"][];
      "Annotation[][path]"?: components["schemas"]["Path"][];
      "Annotation[][destination]"?: components["schemas"]["Destination"][];
    };
    DRAViaFile: {
      /** @enum {string} */
      db?: "DRA";
      "Submission[file]"?: components["schemas"]["File"];
      "Submission[path]"?: components["schemas"]["Path"];
      "Submission[destination]"?: components["schemas"]["Destination"];
      "Experiment[file]"?: components["schemas"]["File"];
      "Experiment[path]"?: components["schemas"]["Path"];
      "Experiment[destination]"?: components["schemas"]["Destination"];
      "Run[file]"?: components["schemas"]["File"];
      "Run[path]"?: components["schemas"]["Path"];
      "Run[destination]"?: components["schemas"]["Destination"];
      "RunFile[][file]"?: components["schemas"]["File"][];
      "RunFile[][path]"?: components["schemas"]["Path"][];
      "RunFile[][destination]"?: components["schemas"]["Destination"][];
      "Analysis[file]"?: components["schemas"]["File"];
      "Analysis[path]"?: components["schemas"]["Path"];
      "Analysis[destination]"?: components["schemas"]["Destination"];
      "AnalysisFile[][file]"?: components["schemas"]["File"][];
      "AnalysisFile[][path]"?: components["schemas"]["Path"][];
      "AnalysisFile[][destination]"?: components["schemas"]["Destination"][];
    };
    GEAViaFile: {
      /** @enum {string} */
      db?: "GEA";
      "IDF[file]"?: components["schemas"]["File"];
      "IDF[path]"?: components["schemas"]["Path"];
      "IDF[destination]"?: components["schemas"]["Destination"];
      "SDRF[file]"?: components["schemas"]["File"];
      "SDRF[path]"?: components["schemas"]["Path"];
      "SDRF[destination]"?: components["schemas"]["Destination"];
      "ADF[][file]"?: components["schemas"]["File"][];
      "ADF[][path]"?: components["schemas"]["Path"][];
      "ADF[][destination]"?: components["schemas"]["Destination"][];
      "RawDataFile[][file]"?: components["schemas"]["File"][];
      "RawDataFile[][path]"?: components["schemas"]["Path"][];
      "RawDataFile[][destination]"?: components["schemas"]["Destination"][];
      "ProcessedDataFile[][file]"?: components["schemas"]["File"][];
      "ProcessedDataFile[][path]"?: components["schemas"]["Path"][];
      "ProcessedDataFile[][destination]"?: components["schemas"]["Destination"][];
    };
    MetaboBankViaFile: {
      /** @enum {string} */
      db?: "MetaboBank";
      "IDF[file]"?: components["schemas"]["File"];
      "IDF[path]"?: components["schemas"]["Path"];
      "IDF[destination]"?: components["schemas"]["Destination"];
      "SDRF[file]"?: components["schemas"]["File"];
      "SDRF[path]"?: components["schemas"]["Path"];
      "SDRF[destination]"?: components["schemas"]["Destination"];
      "MAF[][file]"?: components["schemas"]["File"][];
      "MAF[][path]"?: components["schemas"]["Path"][];
      "MAF[][destination]"?: components["schemas"]["Destination"][];
      "RawDataFile[][file]"?: components["schemas"]["File"][];
      "RawDataFile[][path]"?: components["schemas"]["Path"][];
      "RawDataFile[][destination]"?: components["schemas"]["Destination"][];
      "ProcessedDataFile[][file]"?: components["schemas"]["File"][];
      "ProcessedDataFile[][path]"?: components["schemas"]["Path"][];
      "ProcessedDataFile[][destination]"?: components["schemas"]["Destination"][];
      "BioSample[file]"?: components["schemas"]["File"];
      "BioSample[path]"?: components["schemas"]["Path"];
      "BioSample[destination]"?: components["schemas"]["Destination"];
    };
    JVarViaFile: {
      /** @enum {string} */
      db?: "JVar";
      "Excel[file]"?: components["schemas"]["File"];
      "Excel[path]"?: components["schemas"]["Path"];
      "Excel[destination]"?: components["schemas"]["Destination"];
      "VariantCallFile[][file]"?: components["schemas"]["File"][];
      "VariantCallFile[][path]"?: components["schemas"]["Path"][];
      "VariantCallFile[][destination]"?: components["schemas"]["Destination"][];
    };
  };
  responses: {
    /** @description The requested process initiated successfully. */
    CreateResponseCreated: {
      content: {
        "application/json": components["schemas"]["Validation"];
      };
    };
    /** @description The requested process could not be initiated. */
    CreateResponseBadRequest: {
      content: {
        "application/json": components["schemas"]["Error"];
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
        "multipart/form-data": components["schemas"]["BioProjectViaFile"] | components["schemas"]["BioSampleViaFile"] | components["schemas"]["TradViaFile"] | components["schemas"]["DRAViaFile"] | components["schemas"]["GEAViaFile"] | components["schemas"]["MetaboBankViaFile"] | components["schemas"]["JVarViaFile"];
      };
    };
  };
  headers: never;
  pathItems: never;
}

export type $defs = Record<string, never>;

export type external = Record<string, never>;

export type operations = Record<string, never>;
