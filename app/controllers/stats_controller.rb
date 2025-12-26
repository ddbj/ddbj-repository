class StatsController < ApplicationController
  skip_before_action :authenticate!

  def index
    config = Rails.application.config_for(:sequence)

    render json: {
      sequences: Sequence.order(:id).map {|seq|
        prefixes = config.fetch(seq.scope.to_sym)
        total    = prefixes.sum { 10 ** it[:digits] - 1 }
        i        = prefixes.index { it[:prefix] == seq.prefix }
        used     = prefixes.take(i).sum { 10 ** it[:digits] - 1 } + (seq.next - 1)

        {
          scope:     seq.scope,
          next:      "#{seq.prefix}#{seq.next.to_s.rjust(prefixes[i][:digits], '0')}",
          total:,
          used:,
          remaining: total - used
        }
      }
    }
  end
end
