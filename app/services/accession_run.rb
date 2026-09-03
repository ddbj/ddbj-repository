# "SAMD00412919–936" — a run of allocated numbers, as a curator checks it.
#
# What they want to know after an issuance is that the numbers exist and
# which ones they are, and eighteen lines of SAMD do not say that better
# than two ends and a dash.
#
# Lives apart from both readers because it has two: the run page reads it
# off the issuance row, and the activity feed reads it out of an event
# recorded months earlier — so the formatting cannot belong to either.
#
# Reading a range that somebody wrote, rather than labelling one that was
# allocated, is AccessionRange — which is also where the two ends come
# from, because accessions order by their number and not by their
# characters.
module AccessionRun
  # The tail is trimmed to where the two ends diverge, but never below
  # this: "SAMD00412919–36" invites a misread as a two-digit number,
  # "–936" does not.
  MIN_DIGITS = 3

  def self.label(accessions)
    accessions = Array(accessions)

    return nil              if accessions.empty?
    return accessions.first if accessions.one?

    first, last = accessions.minmax_by { AccessionRange.sort_key(it) }
    shared      = first.chars.zip(last.chars).take_while { it.first == it.last }.size

    "#{first}–#{last[[shared, last.size - MIN_DIGITS].min..]}"
  end
end
