# frozen_string_literal: true

module DDBJRecord
  module V3
    # Per-class `build_<type>(hash) -> Data instance` helpers. The handler /
    # streaming parser stops at hash boundaries and passes raw Hashes here;
    # this module pulls only the fields declared on the matching Data class.
    module Builders
      # Build a Data.define-backed value type, picking up only its declared
      # members and ignoring any extras the input carries. Hash keys are
      # expected as strings (the JSON parser keeps them as strings).
      def build(klass, hash)
        return nil if hash.nil?

        klass.new(**klass.members.to_h {|m| [m, hash[m.to_s]] })
      end

      # Top-level
      def build_root(h)                       = build(Root, h)
      def build_provenance(h)                 = build(Provenance, h)
      def build_gff_meta(h)                   = build(GffMeta, h)

      # Submission
      def build_submission(h)                 = build(Submission, h)
      def build_st26_meta(h)                  = build(St26Meta, h)
      def build_application_identification(h) = build(ApplicationIdentification, h)
      def build_invention_title(h)            = build(InventionTitle, h)

      # Project
      def build_project(h)                    = build(Project, h)
      def build_publication(h)                = build(Publication, h)
      def build_grant(h)                      = build(Grant, h)
      def build_project_target(h)             = build(ProjectTarget, h)

      # Sample
      def build_sample(h)                     = build(Sample, h)

      # SRA-style
      def build_experiment(h)                 = build(Experiment, h)
      def build_library_descriptor(h)         = build(LibraryDescriptor, h)
      def build_platform(h)                   = build(Platform, h)
      def build_spot_descriptor(h)            = build(SpotDescriptor, h)
      def build_read_spec(h)                  = build(ReadSpec, h)
      def build_pipeline_step(h)              = build(PipelineStep, h)
      def build_run(h)                        = build(Run, h)
      def build_data_file(h)                  = build(DataFile, h)
      def build_analysis(h)                   = build(Analysis, h)

      # Sequences / features
      def build_sequences(h)                  = build(Sequences, h)
      def build_source(h)                     = build(Source, h)
      def build_entry(h)                      = build(Entry, h)
      def build_source_feature(h)             = build(SourceFeature, h)
      def build_structured_comment(h)         = build(StructuredComment, h)
      def build_feature(h)                    = build(Feature, h)
      def build_qualifier(h)                  = build(Qualifier, h)

      # Assembly / Dataset / AccessControl
      def build_assembly(h)                   = build(Assembly, h)
      def build_dataset(h)                    = build(Dataset, h)
      def build_access_control(h)             = build(AccessControl, h)
      def build_policy(h)                     = build(Policy, h)
      def build_dac(h)                        = build(Dac, h)

      # Relations
      def build_relation(h)                   = build(Relation, h)
      def build_relation_source(h)            = build(RelationSource, h)
      def build_relation_target(h)            = build(RelationTarget, h)

      # Shared value types
      def build_organism(h)                   = build(Organism, h)
      def build_person(h)                     = build(Person, h)
      def build_organization(h)               = build(Organization, h)
      def build_address(h)                    = build(Address, h)
      def build_attribute(h)                  = build(Attribute, h)
    end
  end
end
