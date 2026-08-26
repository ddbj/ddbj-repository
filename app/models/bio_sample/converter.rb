# frozen_string_literal: true

module BioSample
  # D-way BioSample EAV → DDBJ Record v3 hash. Phase 5 spike scope:
  # enough fields to drive the admin show page (1 submission with N
  # samples in the samples array).
  #
  # Well-known attributes (organism, taxonomy_id, sample_title) are
  # lifted out of the EAV bag into v3-typed sample fields for
  # convenience; the same value also survives in
  # samples[*].attributes. Blank-value EAV rows ARE dropped from the
  # attribute bag for canonicalisation cleanliness; an audit comparing
  # D-way row counts to v3 attribute counts will disagree on those
  # placeholder rows. Phase 6 should decide whether to keep blanks
  # (faithful row-count audit) or strip them (cleaner v3 records).
  class Converter
    SOURCE_FORMAT = 'dway_bs_eav'

    def initialize(submission:)
      @submission = submission
    end

    def call
      {
        'schema_version' => 'v3',
        'provenance'     => {'source_format' => SOURCE_FORMAT},
        'submission'     => submission_block,
        'samples'        => @submission.samples.map {|s| sample_block(s) }
      }.compact
    end

    private

    def submission_block
      org_block = organization_block

      block = {
        'submitters' => @submission.contacts.filter_map {|c|
          # PG returns SQL empty strings as `""` (not nil); `.compact`
          # would only drop nils, so guard each field with `.presence`
          # to drop empty-string fields cleanly. Mirrors BP Converter.
          person = {
            'email'      => c.email.presence,
            'first_name' => c.first.presence,
            'last_name'  => c.last.presence
          }.compact.presence

          next nil unless person

          # v3 Person.organizations is `list[Organization]`; D-way has
          # one organization per submission shared across all contacts,
          # so we lift it as a single-element array.
          person['organizations'] = [org_block] if org_block
          person
        }
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }

      # NOTE: the D-way staging `comment` column is intentionally NOT
      # carried into v3. It is a curator-internal note (visible only to
      # other curators) and not part of the DDBJ Record contract — the
      # Importer copies it to Submission#curator_comment as a typed AR
      # column instead. v3 `submission.comments` remains a legitimate
      # slot for submitter-visible commentary (e.g. Trad genome
      # submissions), just not the one D-way's BS comment maps to.
      block.presence
    end

    def organization_block
      {
        'name' => @submission.organization,
        'url'  => @submission.organization_url
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }.presence
    end

    def sample_block(sample)
      attrs_by_name = sample.attributes.to_h {|a| [a['name'], a['value']] }

      {
        'accession'   => sample.accession,
        'alias'       => sample.sample_name,
        'title'       => attrs_by_name['sample_title'].presence,
        # Same lift-but-retain convention as `title` and `organism` — the
        # value reaches v3 `Sample.description` AND stays in the attribute
        # bag, so an audit comparing EAV row counts can still reconcile.
        # `description` is one of the most common BS attributes (~17k
        # staging samples) and the v3 slot is freeform `str | None`.
        'description' => attrs_by_name['description'].presence,
        'package'     => package_name(sample),
        'organism'    => organism_block(attrs_by_name),
        'attributes'  => sample.attributes.filter_map {|a|
          next nil if a['value'].blank?
          {'name' => a['name'], 'value' => a['value']}
        }.presence
      }.compact
    end

    # D-way は BioSample のパッケージを `package` と `env_package` の 2 列に分けて
    # 持ち、XML の `<Model>` を書くときに合成する。合成規則は bscommon の
    # `AttributeValidator.createPackage` そのもので、`no_package` / 空 / NULL は
    # 「環境パッケージ無し」を意味する番兵なので接尾辞を付けない。`package_group` は
    # 合成に使わない（D-way 側にも「packageGroup は検索には使用しない」と明記がある）。
    #
    # BioSample のパッケージ名として通用するのは合成後の名前のほうで、公開データも
    # validator のカタログもその語彙である。合成しないと `MIMS.me` や
    # `MIMARKS.survey`（環境パッケージが必須の族の、族名だけ）が残り、未知パッケージ
    # として弾かれた上で、パッケージ定義に依存するルール（必須属性 BS_R0027 等）が
    # 軒並み評価されなくなる — 「検証したが指摘なし」と区別が付かない壊れ方をする。
    NO_ENV_PACKAGE = 'no_package'

    def package_name(sample)
      return nil if sample.package.blank?

      env = sample.env_package

      env.blank? || env == NO_ENV_PACKAGE ? sample.package : "#{sample.package}.#{env}"
    end

    def organism_block(attrs_by_name)
      # `Integer(_, exception: false)` rejects non-numeric staging values
      # ('unknown', 'N/A', 'sp.') by returning nil rather than silently
      # coercing them to 0 via String#to_i.
      tax  = Integer(attrs_by_name['taxonomy_id'].to_s, 10, exception: false)
      name = attrs_by_name['organism'].presence

      return nil unless tax || name

      {
        'taxonomy_id' => tax,
        'name'        => name
      }.compact
    end
  end
end
