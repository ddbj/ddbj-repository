module DDBJRecord
  module V3
    PipelineStep = Data.define(
      :step_index,
      :prev_step_index,
      :program,
      :version
    )
  end
end
