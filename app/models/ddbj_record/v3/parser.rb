# frozen_string_literal: true

module DDBJRecord
  module V3
    # Build a DDBJRecord::V3::Root from a JSON IO.
    #
    # Phase 2 implementation: full-document parse via Oj. Streaming support
    # for /samples /experiments /runs /analyses /features /sequences/entries
    # lands in Phase 2.C-bis once the rest of the V3 stack is in place.
    class Parser
      include Builders

      def self.parse(io)
        new.parse(io)
      end

      def parse(io)
        raw = io.respond_to?(:read) ? io.read : io.to_s

        build_root_deep(Oj.load(raw, mode: :strict))
      end

      private

      # Cascade builders down through the nested hash so every level becomes
      # the appropriate Data instance instead of a raw Hash.
      def build_root_deep(h)
        return nil if h.nil?

        h = h.dup

        h['provenance']  = build_provenance_deep(h['provenance']) if h['provenance']
        h['submission']  = build_submission_deep(h['submission']) if h['submission']
        h['project']     = build_project_deep(h['project'])       if h['project']
        h['samples']     = Array(h['samples']).map      {|s| build_sample_deep(s) }     if h['samples']
        h['experiments'] = Array(h['experiments']).map  {|e| build_experiment_deep(e) } if h['experiments']
        h['runs']        = Array(h['runs']).map         {|r| build_run_deep(r) }        if h['runs']
        h['analyses']    = Array(h['analyses']).map     {|a| build_analysis_deep(a) }   if h['analyses']
        h['sequences']   = build_sequences_deep(h['sequences'])   if h['sequences']
        h['features']    = Array(h['features']).map     {|f| build_feature_deep(f) }    if h['features']
        h['assembly']    = build_assembly_deep(h['assembly'])     if h['assembly']
        h['datasets']    = Array(h['datasets']).map     {|d| build_dataset_deep(d) }    if h['datasets']
        h['relations']   = Array(h['relations']).map    {|r| build_relation_deep(r) }   if h['relations']

        h['access_control'] = build_access_control_deep(h['access_control']) if h['access_control']

        build_root(h)
      end

      def build_provenance_deep(h)
        h = h.dup
        h['gff'] = build_gff_meta(h['gff']) if h['gff']

        build_provenance(h)
      end

      def build_submission_deep(h)
        h = h.dup

        h['submitters'] = Array(h['submitters']).map {|p| build_person_deep(p) } if h['submitters']
        h['st26']       = build_st26_meta_deep(h['st26']) if h['st26']
        h['attributes'] = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_submission(h)
      end

      def build_st26_meta_deep(h)
        h = h.dup

        h['application']      = build_application_identification(h['application'])      if h['application']
        h['earliest_priority'] = build_application_identification(h['earliest_priority']) if h['earliest_priority']
        h['invention_titles'] = Array(h['invention_titles']).map {|t| build_invention_title(t) } if h['invention_titles']

        build_st26_meta(h)
      end

      def build_project_deep(h)
        h = h.dup

        h['organism']     = build_organism(h['organism']) if h['organism']
        h['publications'] = Array(h['publications']).map {|p| build_publication_deep(p) } if h['publications']
        h['grants']       = Array(h['grants']).map {|g| build_grant(g) } if h['grants']
        h['target']       = build_project_target(h['target']) if h['target']
        h['attributes']   = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_project(h)
      end

      def build_publication_deep(h)
        h = h.dup
        h['authors'] = Array(h['authors']).map {|p| build_person_deep(p) } if h['authors']

        build_publication(h)
      end

      def build_sample_deep(h)
        h = h.dup
        h['organism']   = build_organism(h['organism']) if h['organism']
        h['attributes'] = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_sample(h)
      end

      def build_experiment_deep(h)
        h = h.dup

        h['library']         = build_library_descriptor(h['library']) if h['library']
        h['platform']        = build_platform(h['platform'])          if h['platform']
        h['spot_descriptor'] = build_spot_descriptor_deep(h['spot_descriptor']) if h['spot_descriptor']
        h['processing']      = Array(h['processing']).map {|p| build_pipeline_step(p) } if h['processing']
        h['attributes']      = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_experiment(h)
      end

      def build_spot_descriptor_deep(h)
        h = h.dup
        h['reads'] = Array(h['reads']).map {|r| build_read_spec(r) } if h['reads']

        build_spot_descriptor(h)
      end

      def build_run_deep(h)
        h = h.dup
        h['files']      = Array(h['files']).map {|f| build_data_file(f) } if h['files']
        h['attributes'] = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_run(h)
      end

      def build_analysis_deep(h)
        h = h.dup
        h['files']      = Array(h['files']).map {|f| build_data_file(f) } if h['files']
        h['processing'] = Array(h['processing']).map {|p| build_pipeline_step(p) } if h['processing']
        h['attributes'] = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_analysis(h)
      end

      def build_sequences_deep(h)
        h = h.dup

        h['common_source']       = build_source_deep(h['common_source']) if h['common_source']
        h['entries']             = Array(h['entries']).map {|e| build_entry_deep(e) } if h['entries']
        h['structured_comments'] = Array(h['structured_comments']).map {|c| build_structured_comment(c) } if h['structured_comments']
        h['attributes']          = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_sequences(h)
      end

      def build_source_deep(h)
        h = h.dup
        h['organism'] = build_organism(h['organism']) if h['organism']
        # qualifiers stays as Hash<String, Array<Qualifier>>; build_qualifier on each leaf
        if h['qualifiers']
          h['qualifiers'] = h['qualifiers'].transform_values {|list| Array(list).map {|q| build_qualifier(q) } }
        end

        build_source(h)
      end

      def build_entry_deep(h)
        h = h.dup
        h['source_features'] = Array(h['source_features']).map {|sf| build_source_feature_deep(sf) } if h['source_features']

        build_entry(h)
      end

      def build_source_feature_deep(h)
        h = h.dup
        h['source'] = build_source_deep(h['source']) if h['source']

        build_source_feature(h)
      end

      def build_feature_deep(h)
        h = h.dup
        if h['qualifiers']
          h['qualifiers'] = h['qualifiers'].transform_values {|list| Array(list).map {|q| build_qualifier(q) } }
        end

        build_feature(h)
      end

      def build_assembly_deep(h)
        h = h.dup
        h['organism']   = build_organism(h['organism']) if h['organism']
        h['attributes'] = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_assembly(h)
      end

      def build_dataset_deep(h)
        h = h.dup
        h['attributes'] = Array(h['attributes']).map {|a| build_attribute(a) } if h['attributes']

        build_dataset(h)
      end

      def build_access_control_deep(h)
        h = h.dup
        h['policy'] = build_policy(h['policy']) if h['policy']
        h['dacs']   = Array(h['dacs']).map {|d| build_dac_deep(d) } if h['dacs']

        build_access_control(h)
      end

      def build_dac_deep(h)
        h = h.dup
        h['contacts'] = Array(h['contacts']).map {|p| build_person_deep(p) } if h['contacts']

        build_dac(h)
      end

      def build_relation_deep(h)
        h = h.dup
        h['source'] = build_relation_source(h['source']) if h['source']
        h['target'] = build_relation_target(h['target']) if h['target']

        build_relation(h)
      end

      def build_person_deep(h)
        h = h.dup
        h['organization'] = build_organization_deep(h['organization']) if h['organization']

        build_person(h)
      end

      def build_organization_deep(h)
        h = h.dup
        h['address'] = build_address(h['address']) if h['address']

        build_organization(h)
      end
    end
  end
end
