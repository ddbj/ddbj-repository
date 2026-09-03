require 'test_helper'

# The distinction the module exists to make: "the object store is not
# answering" against "that object is not there". Reading either as the
# other is expensive — a missing object stopping a sweep of fifteen
# thousand rows, or an unreachable store making every submission's
# history read as empty and be overwritten from the source.
#
# Written after a change that moved the line and could not be seen to
# have moved it: the test suite runs on Disk storage, which never
# produces the chain S3 produces, so the case that flipped was reachable
# by nothing.
class StorageFailureTest < ActiveSupport::TestCase
  test 'a store that is not answering is one' do
    assert StorageFailure === Aws::S3::Errors::ServiceUnavailable.new(nil, 'down')
    assert StorageFailure === Aws::S3::Errors::Forbidden.new(nil, 'rotated credential')
    assert StorageFailure === Seahorse::Client::NetworkingError.new(SocketError.new('no route'))
  end

  # A bare 404 says both things and neither: it is what a proxy with
  # nothing to route to answers, and what a gone blob answers. Read as
  # absence it cost a fortnight and 15,657 rows in June 2026, so it stays
  # on the side that costs one wasted run.
  test 'a bare 404 is one' do
    assert StorageFailure === Aws::S3::Errors::NotFound.new(nil, 'Not Found')
  end

  # THE case. ActiveStorage converts NoSuchKey into FileNotFoundError
  # inside a `rescue`, so Ruby records the original as `cause` — and this
  # walk finds it. That is what stops a sweep whose patch blobs have gone
  # rather than letting `safe_prior_materialised` read every chain as
  # empty and rebuild the corpus from D-way.
  #
  # Built the way ActiveStorage and `materialise_at` build it. A hand-made
  # exception has no `cause` and pins nothing.
  test 'an absence that ActiveStorage converted is still one, through the wrapping' do
    assert StorageFailure === wrapped_in_materialisation_failure { raise_converted_absence }
  end

  test 'it walks the cause chain, because the failure rarely arrives bare' do
    assert StorageFailure === wrapped_in_materialisation_failure {
      raise Aws::S3::Errors::ServiceUnavailable.new(nil, 'down')
    }
  end

  test 'anything else is neither' do
    assert_not StorageFailure === StandardError.new('unrelated')
    assert_not StorageFailure === wrapped_in_materialisation_failure { raise Oj::ParseError, 'not json' }
  end

  private

  # What `ActiveStorage::Service::S3Service#download` raises for a key the
  # bucket does not have.
  def raise_converted_absence
    raise Aws::S3::Errors::NoSuchKey.new(nil, 'gone')
  rescue Aws::S3::Errors::NoSuchKey
    raise ActiveStorage::FileNotFoundError
  end

  # What `Submission#materialise_at` does with whatever stopped the replay.
  def wrapped_in_materialisation_failure
    yield
  rescue StandardError => e
    begin
      raise Submission::MaterialisationFailed.new(update_id: 1, original: e)
    rescue Submission::MaterialisationFailed => wrapped
      wrapped
    end
  end
end
