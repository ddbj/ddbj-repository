# frozen_string_literal: true

class Flatfile::Buffer
  def initialize(io)
    @io      = io
    @pending = +''
  end

  def <<(content)
    str = content.to_s

    return self if str.empty?

    parts = str.split("\n", -1)

    @pending << parts.shift

    parts.each do |part|
      wrap @io, @pending

      @pending = +part
    end

    self
  end

  def flush
    wrap @io, @pending unless @pending.empty?

    @pending = +''
  end

  def to_s = ''

  private

  def wrap(io, line)
    if line.size <= 80
      io.puts line.delete_suffix(' ')
      return
    end

    indent = case line
    when /\A((?:COMMENT|\s{7})\s{5})([A-Z]{2})(\s+)/
      ' ' * $1.size + $2 + ' ' * $3.size
    when /\A([A-Z\s]{,12}\s*)/
      ' ' * $1.size
    else
      raise 'unreachable'
    end

    late = line[40..79]

    if i = late.rindex(' ')
      io.puts (line[0..39] + late[0..i]).delete_suffix(' ')

      wrap io, indent + late[(i + 1)..] + line[80..]
    elsif i = %w[, - / ( )].filter_map { late.rindex(it) }.max
      wrap_pos = late[i] == '(' ? i - 1 : i

      io.puts (line[0..39] + late[0..wrap_pos]).delete_suffix(' ')

      wrap io, indent + late[(wrap_pos + 1)..] + line[80..]
    else
      io.puts line[0..79].delete_suffix(' ')

      wrap io, indent + line[80..]
    end
  end
end
