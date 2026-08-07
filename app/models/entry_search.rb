# An ST.26 submission's entries. Searched by the entry's own identifier
# and by its accession number, which are the two things a curator has in
# hand when they arrive here — from a validation finding, or from a
# question quoting an accession.
class EntrySearch < SubmissionRowSearch
  search_columns :entry_id, :accession
end
