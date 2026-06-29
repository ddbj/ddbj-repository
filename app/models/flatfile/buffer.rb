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

  # 80 桁を超える行を、継続行を indent で揃えながら折り返してすべて出力する。
  #
  # 折り返し桁 b（この行に残す末尾の桁）は必ず indent 幅より右に取る。継続行は
  # `indent + 残り` なので、b < indent.size だと行が縮まず無限ループになる。
  # COMMENT 内に埋め込んだ feature table のように indent が 40 桁を超える行
  # （巨大な化学名など空白で折り返せない値）で実際にこれが起きる。再帰実装の
  # 頃は同じ条件で SystemStackError になっていた。
  def wrap(io, line)
    loop do
      if line.size <= 80
        io.puts line
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

      # 空白優先、次に区切り文字、どちらも indent より右に無ければ 80 桁で固定折り。
      # いずれも b >= indent.size を満たすものだけ採用して前進を保証する。
      b =
        if (i = late.rindex(' ')) && 40 + i >= indent.size
          40 + i
        elsif (i = %w[, - / ( )].filter_map { late.rindex(it) }.max) && 40 + (pos = late[i] == '(' ? i - 1 : i) >= indent.size
          40 + pos
        else
          [79, indent.size].max
        end

      io.puts line[0..b].delete_suffix(' ')

      line = indent + line[(b + 1)..]
    end
  end
end
