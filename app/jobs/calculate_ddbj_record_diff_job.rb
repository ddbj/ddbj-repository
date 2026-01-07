class CalculateDDBJRecordDiffJob < ApplicationJob
  CONTEXT = 3

  def perform(update)
    x = update.submission.ddbj_record
    y = update.ddbj_record

    update.update! diff: unified_diff(x.download, y.download, file1: x.filename, file2: y.filename)
  end

  private

  def unified_diff(x, y, file1:, file2:)
    ops         = Diff::LCS.sdiff(x.lines, y.lines)
    change_idxs = ops.each_index.reject { ops[it].action == '=' }
    ranges      = []

    change_idxs.each do |i|
      s = [i - CONTEXT, 0].max
      e = [i + CONTEXT, ops.size - 1].min

      if !ranges.empty? && s <= ranges[-1].end + 1
        ranges[-1] = (ranges[-1].begin..[ranges[-1].end, e].max)
      else
        ranges << (s..e)
      end
    end

    out = <<~DIFF
      --- a/#{file1}
      +++ b/#{file2}
    DIFF

    ranges.each do |range|
      slice = ops[range]

      old_positions = slice.map(&:old_position).compact
      new_positions = slice.map(&:new_position).compact

      old_start = (old_positions.min || 0) + 1
      new_start = (new_positions.min || 0) + 1

      old_len = slice.count { it.action != '+' }
      new_len = slice.count { it.action != '-' }

      out << "@@ -#{old_start},#{old_len} +#{new_start},#{new_len} @@\n"

      slice.each do |change|
        case change.action
        when '='
          out << " #{change.old_element}"
        when '!'
          out << "-#{change.old_element}"
          out << "+#{change.new_element}"
        when '-'
          out << "-#{change.old_element}"
        when '+'
          out << "+#{change.new_element}"
        end
      end
    end

    out
  end
end
