module PublicXML
  module DRA
    # What a DRA submission publishes: its record as SRA XML
    # (::DRA::XMLRenderer), less what D-way's release (drabatch ReleaseData)
    # left out of the public copy —
    #
    #   - the submission's CONTACTS and ACTIONS: who to write to, and what
    #     the submitter asked to be done (a hold until a date)
    #   - a run's DATA_BLOCK: the names of the files sent, which are not
    #     what is published
    #
    # — and with every object named by its accession: its alias, and both
    # the accession and the refname of what refers to it (an analysis's
    # targets too), which may have named it by an alias of the submitter's
    # own; and with the submission's center on the objects in it, as
    # D-way's form put it there. Written as D-way wrote them, indented four
    # spaces.
    #
    # Each document is checked against the version it is written in, as
    # D-way's were; one that is not valid is refused (Invalid) rather than
    # published.
    module Documents
      class Invalid < StandardError; end

      # Each element whose refname names an object of the record's, by the
      # list it is in.
      REFERENCES = {
        'STUDY_REF'         => 'projects',
        'SAMPLE_DESCRIPTOR' => 'samples',
        'MEMBER'            => 'samples',
        'DEFAULT_MEMBER'    => 'samples',
        'EXPERIMENT_REF'    => 'experiments'
      }.freeze

      # The documents whose objects take the submission's center.
      CENTERED = %w[EXPERIMENT_SET RUN_SET ANALYSIS_SET].freeze

      # An analysis's TARGET names the list by its SRA object type.
      TARGETS = {
        'STUDY'      => 'projects',
        'SAMPLE'     => 'samples',
        'EXPERIMENT' => 'experiments',
        'RUN'        => 'runs',
        'ANALYSIS'   => 'analyses'
      }.freeze

      module_function

      # {kind => XML}, for each kind the record has objects of.
      def call(record)
        documents(record).to_h {|kind, document|
          errors = ::DRA::XSD.schema(kind).validate(document)

          raise Invalid, "#{kind}: #{errors.first(3).map(&:message).join('; ')}" if errors.any?

          [kind, document.to_xml(encoding: 'UTF-8', indent: 4)]
        }
      end

      # What the record publishes, valid or not: a change to anything else
      # it says is no change to a published submission
      # (Submission#republish_changed!).
      def published_view(record) = documents(record).transform_values(&:to_xml)

      def documents(record) = ::DRA::XMLRenderer.new(record).call.each_value { trim it, record }

      def trim(document, record)
        document.xpath('/SUBMISSION/CONTACTS | /SUBMISSION/ACTIONS | //RUN/DATA_BLOCK').each(&:remove)

        roots = document.root.name.end_with?('_SET') ? document.root.element_children : [document.root]

        roots.each do |object|
          object['alias'] = object['accession'] if object['accession']
        end

        center_of_submission document, roots, record

        references = ::DDBJRecord::References::Index.new(record)

        document.xpath([*REFERENCES.keys.map { "//#{it}" }, '//TARGETS/TARGET'].join(' | ')).each do |reference|
          name_by_accession reference, references
        end

        document.xpath('//TARGETS[not(*)]').each(&:remove)
      end

      # The submission's center is its experiments', runs' and analyses' too,
      # and the center a run names its experiment's: D-way's form took one
      # Organization for the submission and wrote it into all of them. One
      # with a center of its own keeps it.
      def center_of_submission(document, roots, record)
        center = record.dig('submission', 'center_name').presence if record['submission'].is_a?(Hash)

        return unless center && CENTERED.include?(document.root.name)

        roots.each do |object|
          object['center_name'] ||= center
        end

        document.xpath('//RUN/EXPERIMENT_REF').each do |reference|
          reference['refcenter'] ||= center
        end
      end

      # D-way set the refname to the accession whatever it had been, and so
      # dropped a refname naming nothing with one — an object of another
      # submission's, or of none: the submitter's alias is not published.
      # Nor, then, is an analysis's target with nothing else to name it by;
      # it is one of several, and says what the analysis was made from.
      def name_by_accession(reference, references)
        list      = reference.name == 'TARGET' ? TARGETS[reference['sra_object_type']] : REFERENCES.fetch(reference.name)
        accession = reference['accession'] || (references.resolve(list, name: reference['refname'])&.[]('accession') if list && reference['refname'])

        if accession
          reference['accession'] = reference['refname'] = accession
        elsif reference.name == 'TARGET' && !reference.at_xpath('IDENTIFIERS')
          reference.remove
        else
          reference.remove_attribute 'refname'
        end
      end

      private_class_method :documents, :trim, :center_of_submission, :name_by_accession
    end
  end
end
