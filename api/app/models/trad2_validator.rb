class Trad2Validator
  include TradValidation

  ASSOC = {
    'Sequence'   => %w(.fasta .seq.fa .fa .fna .seq),
    'Annotation' => %w(.gff),
    'Metadata'   => %w(.tsv)
  }

  def validate(validation)
    objs = validation.objs.without_base

    objs.each do |obj|
      obj.validation_details = []
    end

    validate_ext   objs, ASSOC
    validate_nwise objs, ASSOC
    validate_seq   objs

    objs.each do |obj|
      if obj.validation_details.empty?
        obj.update! validity: 'valid', validation_details: nil
      else
        obj.validity_invalid!
      end
    end
  end
end
