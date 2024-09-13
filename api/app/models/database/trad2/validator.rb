class Database::Trad2::Validator
  include TradValidation

  ASSOC = {
    "Sequence"   => %w[.fasta .seq.fa .fa .fna .seq],
    "Annotation" => %w[.gff],
    "Metadata"   => %w[.tsv]
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

  def validate_ann(objs)
    objs.select { _1._id == "Annotation" }.each do |obj|
      NoodlesGFF.parse obj.file.download
    rescue NoodlesGFF::Error => e
      obj.validation_details.create!(
        severity: "error",
        message:  e.message
      )
    end
  end
end
