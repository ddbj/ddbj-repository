# A span of accessions written the way a submitter has them in hand:
# `SAMD00000001-SAMD00000050`, the first and the last of a block.
#
# It names a filter, never a list. What it shares is whichever of the
# caller's own accessions in the set fall inside it, so a range wider than
# what they hold is not an error and a gap in the middle is not one
# either — the same two properties that make "everything except these
# three" writable as a range that stops before them.
#
# Numeric, not lexical. BioSample pads its numbers (`SAMD00000001`) and
# BioProject does not (`PRJDB502`), so comparing the strings would put
# PRJDB1000 before PRJDB999 and quietly name the wrong block. `sort_key`
# below is the one place that knows this, and AccessionRun sorts by it too.
class AccessionRange < Data.define(:prefix, :from, :to, :written)
  # Prefix then digits, which is the shape of every accession the three
  # databases issue. Anything else is not a range and is not silently
  # treated as one.
  PATTERN = /\A([A-Za-z][A-Za-z_]*)(\d+)\z/

  # The series and the number, or nil for a string that is not shaped like
  # an accession.
  def self.split(accession)
    parts = PATTERN.match(accession) or return nil

    [parts[1].upcase, parts[2].to_i]
  end

  # How accessions order. The fallback keeps a string that is not an
  # accession comparable with one that is, rather than raising in the
  # middle of a sort.
  def self.sort_key(accession) = split(accession) || [accession.to_s.upcase, 0]

  # nil rather than an exception: the caller has a sentence to say about a
  # token it cannot read, and it names the token.
  def self.parse(token)
    first, last, *rest = token.split('-')

    return nil unless last && rest.empty?

    from = split(first) or return nil
    to   = split(last)  or return nil

    return nil unless from.first == to.first

    low, high = [from.last, to.last].minmax

    new(prefix: from.first, from: low, to: high, written: token)
  end

  # Whether a range could have been meant at all, so that a token with a
  # hyphen in it is reported as an unreadable range rather than looked up
  # as an accession nobody has.
  def self.written_as_range?(token) = token.include?('-')

  def cover?(accession)
    series, number = self.class.split(accession)

    return false if series.nil?

    include?(series, number)
  end

  # The same question with the reading already done. A caller checking one
  # accession against many ranges splits it once and asks this: `cover?`
  # would re-read the same string once per range, which on a hundred
  # thousand samples against a pasted page of ranges is twenty million
  # regexp matches to answer a question about integers.
  def include?(series, number) = series == prefix && (from..to).cover?(number)

  # What was typed, not what it parsed to. A reader told that nothing
  # falls in `SAMD9000-SAMD9999` when they wrote `SAMD00009000-…` has to
  # work out whether the padding was the problem before they can see that
  # the prefix was.
  def to_s = written
end
