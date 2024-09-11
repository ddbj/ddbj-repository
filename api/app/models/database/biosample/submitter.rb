class Database::BioSample::Submitter
  def submit(submission)
    user         = submission.validation.user
    submitter_id = user.uid

    BioSample::Record.transaction isolation: Rails.env.test? ? nil : :serializable do |tx|
      submission_id = next_submission_id

      BioSample::SubmissionForm.create!(
        submission_id:,
        status_id: :new
      )

      content = submission.validation.objs.find_by!(_id: "BioSample").file.download
      doc     = Nokogiri::XML.parse(content)

      BioSample::ContactForm.insert_all doc.xpath("/BioSample/Owner/Contacts/Contact").map.with_index(1) { |contact, i|
        first_name = contact.at("Name/First")
        last_name  = contact.at("Name/Last")
        email      = contact[:email]

        {
          submission_id:,
          first_name:    first_name.text,
          last_name:     last_name.text,
          email:,
          seq_no:        i
        }
      }

      package_id = doc.at("/BioSample/Models/Model").text

      package_attributes(package_id) => { package_group:, env_package: }

      attribute_file = CSV.generate(col_sep: "\t") { |tsv|
        doc.xpath("/BioSample/Attributes/Attribute").map { |attribute|
          [
            attribute[:attribute_name],
            attribute.text
          ]
        }.transpose.each do |row|
          tsv << row
        end
      }

      BioSample::SubmissionForm.create!(
        submission_id:,
        submitter_id:,
        organization:        doc.at("/BioSample/Owner/Name")&.text,
        organization_url:    doc.at("/BioSample/Owner/Name/@url")&.text,
        release_type:        submission.visibility_public? ? :release : :hold,
        attribute_file_name: "#{submission_id}.tsv",
        attribute_file:,
        comment:             doc.at("/BioSample/Description/Comment/Paragraph")&.text,
        package_group:,
        package:             package_id,
        env_package:
      )

      BioSample::LinkForm.insert_all! doc.xpath("/BioSample/Links/Link").map.with_index(1) { |link, i|
        {
          submission_id:,
          seq_no:        i,
          description:   link[:label],
          url:           link.text
        }
      }

      tx.after_commit do
        DRMDB::ExtEntity.create!(
          acc_type: :study,
          ref_name: submission_id,
          status:   :inputting
        ) do |entity|
          entity.ext_permits.build(
            submitter_id:
          )
        end
      end
    end
  end

  private

  def next_submission_id
    submission_id = BioSample::SubmissionForm.order(submission_id: :desc).pick(:submission_id) || "SSUB000000"
    num           = submission_id.delete_prefix("SSUB").to_i

    "SSUB#{num.succ.to_s.rjust(6, '0')}"
  end

  def package_attributes(package_id)
    res = Fetch::API.fetch("#{DDBJ_VALIDATOR_URL}/package_group_list")

    raise res.inspect unless res.ok

    body = res.json

    packages_assoc       = body.flat_map { _1.fetch(:package_list) }.index_by { _1.fetch(:package_id) }
    package_groups_assoc = body.index_by { _1.fetch(:package_group_uri) }

    package       = packages_assoc.fetch(package_id)
    package_group = package_groups_assoc.fetch(package.fetch(:parent_package_group_uri))

    {
      package_group: package_group.fetch(:package_group_id),
      env_package:   package.fetch(:env_package)
    }
  end
end
