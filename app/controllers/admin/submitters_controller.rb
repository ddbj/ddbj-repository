module Admin
  # Curator edit to v3 `submission.submitters: list[Person]`. Goes through
  # the patch chain via Submission#append_update! — same shape as the
  # comments edit. Form posts a positional array of submitter Hashes;
  # we filter blanks, drop empty submitter rows entirely, and let the
  # Canonicalizer.diff emit minimal RFC 6902 ops.
  class SubmittersController < ApplicationController
    PERSON_FIELDS   = %w[email first_name last_name].freeze
    ORG_FIELDS      = %w[name role type url].freeze

    def update
      submission = Submission.find(params[:submission_id])

      new_submitters = build_submitters(submitters_params)
      new_record     = patched_record(submission, new_submitters)

      result = submission.append_update!(
        new_record,
        actor:  "admin:#{current_user.uid}",
        source: :manual
      )

      message = result ? "Submitters saved (chain length now #{submission.updates.count})." \
                       : 'Submitters unchanged — no patch generated.'

      redirect_to admin_submission_path(submission), notice: message
    rescue Submission::MaterialisationFailed => e
      redirect_to admin_submission_path(submission),
                  alert: "Cannot edit: existing patch chain is unreadable (#{e.class}: #{e.message})."
    end

    private

    def submitters_params
      params.permit(submitters: PERSON_FIELDS + [{organizations: ORG_FIELDS}]).to_h
    end

    # Build the v3 `submitters` list. Filter blanks per field (`.presence`
    # treats `""` as nil, so the form's leftover empty <input>s don't
    # leak into the record). Drop a submitter row whose every field is
    # blank — that's how the form expresses "remove this submitter" AND
    # how the trailing empty row stays out of the record when the
    # curator wasn't adding one.
    #
    # Form params arrive as `submitters[0][...]`, `submitters[1][...]`
    # which Rails parses as `{submitters: {"0" => {...}, "1" => {...}}}`
    # (Hash with stringified-integer keys, ordered by insertion). We
    # walk `.values` to recover positional order.
    def build_submitters(raw)
      rows(raw[:submitters] || raw['submitters']).filter_map {|s|
        person = PERSON_FIELDS.each_with_object({}) {|f, h|
          val = s[f] || s[f.to_sym]
          h[f] = val.presence if val
        }.compact

        orgs = build_orgs(s[:organizations] || s['organizations'])
        person['organizations'] = orgs if orgs.any?

        person.presence
      }
    end

    def build_orgs(raw)
      rows(raw).filter_map {|o|
        ORG_FIELDS.each_with_object({}) {|f, h|
          val = o[f] || o[f.to_sym]
          h[f] = val.presence if val
        }.compact.presence
      }
    end

    # `submitters[0][...]` form syntax arrives as Hash; `submitters[][...]`
    # as Array. Normalise either to an Array of row Hashes.
    def rows(raw)
      case raw
      when Hash  then raw.values
      when Array then raw
      else            []
      end
    end

    def patched_record(submission, submitters)
      record = submission.materialised_record.deep_dup
      block  = record['submission'] ||= {}

      if submitters.any?
        block['submitters'] = submitters
      else
        block.delete('submitters')
      end

      record.delete('submission') if block.empty?
      record
    end
  end
end
