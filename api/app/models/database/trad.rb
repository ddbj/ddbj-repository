module Database::Trad
  class Param
    def self.build(params)
      nil
    end
  end

  class Validator
    class MissingContactPersonInformation < StandardError; end
    class DuplicateContactPersonInformation < StandardError; end

    include TradValidation

    ASSOC = {
      "Sequence"   => %w[.fasta .seq.fa .fa .fna .seq],
      "Annotation" => %w[.ann .annt.tsv .ann.txt]
    }

    def validate(validation)
      objs = validation.objs.without_base

      validate_ext   objs, ASSOC
      validate_nwise objs, ASSOC
      validate_seq   objs
      validate_ann   objs

      objs.each do |obj|
        if obj.validation_details.empty?
          obj.validity_valid!
        else
          obj.validity_invalid!
        end
      end
    end

    private

    def validate_ann(objs)
      anns = objs.select { _1._id == "Annotation" }

      return if anns.empty?

      assoc = anns.map { |obj|
        begin
          contact_person = extract_contact_person_in_ann(obj.file)
        rescue MissingContactPersonInformation
          obj.validation_details.create!(
            severity: "error",
            message:  "Contact person information (contact, email, institute) is missing."
          )
        rescue DuplicateContactPersonInformation
          obj.validation_details.create!(
            severity: "error",
            message:  "Contact person information (contact, email, institute) is duplicated."
          )
        end


        [ obj, contact_person ]
      }

      _, first_contact_person = assoc.first

      assoc.each do |obj, contact_person|
        unless first_contact_person == contact_person
          obj.validation_details.create!(
            severity: "error",
            message:  "Contact person must be the same for all annotation files."
          )
        end
      end
    end

    def extract_contact_person_in_ann(file)
      in_common = false
      contact   = nil
      email     = nil
      institute = nil

      file.download.each_line chomp: true do |line|
        entry, _feature, _location, qualifier, value = line.split("\t")

        break if in_common && entry.present?

        in_common = entry == "COMMON" if entry.present?

        next unless in_common

        case qualifier
        when "contact"
          raise DuplicateContactPersonInformation if contact

          contact = value
        when "email"
          raise DuplicateContactPersonInformation if email

          email = value
        when "institute"
          raise DuplicateContactPersonInformation if institute

          institute = value
        else
          # do nothing
        end
      end

      raise MissingContactPersonInformation unless contact && email && institute

      {
        contact:,
        email:,
        institute:
      }
    end
  end

  class Submitter
    def submit(submission)
      # do nothing
    end
  end
end
