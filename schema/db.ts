export default [
  {
    "id": "BioProject",
    "objects": {
      "file": [
        {
          "id": "BioProject",
          "ext": "xml",
          "required": true,
          "multiple": false
        }
      ],
      "ddbj_record": []
    }
  },
  {
    "id": "BioSample",
    "objects": {
      "file": [
        {
          "id": "BioSample",
          "ext": "xml",
          "required": true,
          "multiple": false
        }
      ],
      "ddbj_record": []
    }
  },
  {
    "id": "Trad",
    "objects": {
      "file": [
        {
          "id": "Sequence",
          "ext": "fasta",
          "required": true,
          "multiple": true
        },
        {
          "id": "Annotation",
          "ext": "ann",
          "required": true,
          "multiple": true
        }
      ],
      "ddbj_record": [
        {
          "id": "DDBJ Record",
          "ext": "json",
          "required": true,
          "multiple": false
        }
      ]
    }
  },
  {
    "id": "DRA",
    "objects": {
      "file": [
        {
          "id": "Submission",
          "ext": "xml",
          "required": true,
          "multiple": false
        },
        {
          "id": "Experiment",
          "ext": "xml",
          "required": true,
          "multiple": false
        },
        {
          "id": "Run",
          "ext": "xml",
          "required": true,
          "multiple": false
        },
        {
          "id": "RunFile",
          "ext": "fastq",
          "required": true,
          "multiple": true
        },
        {
          "id": "Analysis",
          "ext": "xml",
          "required": false,
          "multiple": false
        },
        {
          "id": "AnalysisFile",
          "ext": "raw",
          "required": false,
          "multiple": true
        }
      ],
      "ddbj_record": []
    }
  },
  {
    "id": "GEA",
    "objects": {
      "file": [
        {
          "id": "IDF",
          "ext": "idf.txt",
          "required": true,
          "multiple": false
        },
        {
          "id": "SDRF",
          "ext": "sdrf.txt",
          "required": true,
          "multiple": false
        },
        {
          "id": "ADF",
          "ext": "adf.txt",
          "required": false,
          "multiple": true
        },
        {
          "id": "RawDataFile",
          "ext": "raw",
          "required": false,
          "multiple": true
        },
        {
          "id": "ProcessedDataFile",
          "ext": "raw",
          "required": false,
          "multiple": true
        }
      ],
      "ddbj_record": []
    }
  },
  {
    "id": "MetaboBank",
    "objects": {
      "file": [
        {
          "id": "IDF",
          "ext": "idf.txt",
          "required": true,
          "multiple": false
        },
        {
          "id": "SDRF",
          "ext": "sdrf.txt",
          "required": true,
          "multiple": false
        },
        {
          "id": "MAF",
          "ext": "maf.txt",
          "required": false,
          "multiple": true
        },
        {
          "id": "RawDataFile",
          "ext": "raw",
          "required": false,
          "multiple": true
        },
        {
          "id": "ProcessedDataFile",
          "ext": "raw",
          "required": false,
          "multiple": true
        },
        {
          "id": "BioSample",
          "ext": "tsv",
          "required": false,
          "multiple": false
        }
      ],
      "ddbj_record": []
    }
  },
  {
    "id": "JVar",
    "objects": {
      "file": [
        {
          "id": "Excel",
          "ext": "xlsx",
          "required": true,
          "multiple": false
        },
        {
          "id": "VariantCallFile",
          "ext": "vcf",
          "required": false,
          "multiple": true
        }
      ],
      "ddbj_record": []
    }
  },
  {
    "id": "Trad2",
    "objects": {
      "file": [
        {
          "id": "Sequence",
          "ext": "fasta",
          "required": true,
          "multiple": true
        },
        {
          "id": "Annotation",
          "ext": "gff",
          "required": true,
          "multiple": true
        },
        {
          "id": "Metadata",
          "ext": "tsv",
          "required": true,
          "multiple": true
        }
      ],
      "ddbj_record": []
    }
  }
] as const;
