class StatsController < ApplicationController
  skip_before_action :authenticate!

  def index
    render json: {
      # 番号の組み立ても残量の計算も Sequence 側。ここで写すと、払い出しが実際に出す
      # 番号と表示がずれる（pad の有無、prefix の送り待ち）。
      sequences: Sequence.order(:id).map {|seq|
        {
          scope:     seq.scope,
          next:      seq.peek,
          total:     seq.total,
          used:      seq.used,
          remaining: seq.remaining
        }
      },

      taxdump: {
        names_count: Taxdump::Name.count,
        nodes_count: Taxdump::Node.count,
        loaded_at:   Taxdump::Load.maximum(:created_at)
      }
    }
  end
end
