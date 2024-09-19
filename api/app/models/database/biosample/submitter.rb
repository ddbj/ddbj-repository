class Database::BioSample::Submitter
  class SubmissionIDOverflow < StandardError; end

  def submit(submission)
    user         = submission.validation.user
    submitter_id = user.uid

    BioSample::Record.transaction isolation: Rails.env.test? ? nil : :serializable do |tx|
      begin
        submission_id = next_submission_id
      rescue SubmissionIDOverflow
        tx.after_rollback do
          BioSample::OperationHistory.create!(
            type:         :fatal,
            summary:      "[repository:CreateNewSubmission] Number of submission surpass the upper limit",
            date:         Time.current,
            submitter_id:
          )
        end

        raise
      end

      tx.after_rollback do
        BioSample::OperationHistory.create!(
          type:         :error,
          summary:      "[repository:CreateNewSubmission] rollback transaction",
          date:         Time.current,
          submitter_id:
        )
      end

      content = submission.validation.objs.find_by!(_id: "BioSample").file.download
      doc     = Nokogiri::XML.parse(content)

      contacts = biosamples(doc).map { |biosample|
        biosample.xpath("Owner/Contacts/Contact").map { |contact|
          {
            first_name: contact.at("Name/First")&.text,
            last_name:  contact.at("Name/Last")&.text,
            email:      contact[:email]
          }
        }
      }.then { |contacts_list|
        raise "Inconsistent Owner/Contacts/Contact: #{contacts_list.inspect}" if contacts_list.uniq.size > 1

        contacts_list.first
      }

      BioSample::ContactForm.insert_all contacts.map.with_index(1) { |contact, i|
        {
          **contact,
          submission_id:,
          seq_no:        i
        }
      }

      package_id = biosamples(doc).map { |biosample|
        biosample.at("Models/Model")&.text
      }.then { |models|
        raise "Inconsistent Models/Model: #{models.inspect}" if models.uniq.size > 1

        models.first
      }

      package_attributes(package_id) => { package_group:, env_package: }

      attributes_list = biosamples(doc).map { |biosample|
        biosample.xpath("Attributes/Attribute").map { |attribute|
          [
            attribute[:attribute_name],
            attribute.text
          ]
        }.to_h
      }.tap { |attributes_list|
        keys_list = attributes_list.map(&:keys)

        raise "Inconsistent Attributes/Attribute/@attribute_name: #{keys_list.inspect}" if keys_list.uniq.size > 1
      }

      unless attributes_list.empty?
        attribute_file = CSV.generate(col_sep: "\t") { |tsv|
          attributes_list.each_with_index do |attributes, i|
            tsv << attributes.keys if i.zero?
            tsv << attributes.values
          end
        }
      end

      organization = biosamples(doc).map { |biosample|
        biosample.at("Owner/Name")&.text
      }.then { |orgnaizations|
        raise "Inconsistent Owner/Name: #{orgnaizations.inspect}" if orgnaizations.uniq.size > 1

        orgnaizations.first
      }

      organization_url = biosamples(doc).map { |biosample|
        biosample.at("Owner/Name/@url")&.text
      }.then { |organization_urls|
        raise "Inconsistent Owner/Name/@url: #{organization_urls.inspect}" if organization_urls.uniq.size > 1

        organization_urls.first
      }

      comment = biosamples(doc).map { |biosample|
        biosample.at("Description/Comment/Paragraph")&.text
      }.then { |comments|
        raise "Inconsistent Description/Comment/Paragraph: #{comments.inspect}" if comments.uniq.size > 1

        comments.first
      }

      BioSample::SubmissionForm.create!(
        submission_id:,
        submitter_id:,
        status_id:           :new,
        organization:,
        organization_url:,
        release_type:        submission.visibility_public? ? "release" : "hold",
        attribute_file_name: "#{submission_id}.tsv",
        attribute_file:,
        comment:,
        package_group:,
        package:             package_id,
        env_package:
      )

      links = biosamples(doc).map { |biosample|
        biosample.xpath("Links/Link").map { |link|
          {
            description: link[:label],
            url:         link.text
          }
        }
      }.then { |links_list|
        raise "Inconsistent Links/Link: #{links_list.inspect}" if links_list.uniq.size > 1

        links_list.first
      }

      if links
        BioSample::LinkForm.insert_all! links.map.with_index(1) { |link, i|
          {
            **link,
            submission_id:,
            seq_no:        i
          }
        }
      end

      BioSample::OperationHistory.create!(
        type:          :info,
        summary:       "[repository:CreateNewSubmission] Create new submission",
        date:          Time.current,
        submitter_id:,
        submission_id:
      )

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

    raise SubmissionIDOverflow if num >= 999_999

    "SSUB#{num.succ.to_s.rjust(6, '0')}"
  end

  def biosamples(doc, &block)
    doc.xpath("BioSample|BioSampleSet/BioSample")
  end

  def package_attributes(package_id)
    res = Fetch::API.fetch("#{ENV.fetch('DDBJ_VALIDATOR_URL')}/package_group_list")

    raise res.inspect unless res.ok

    body = res.json

    collect_packages = ->(packages) {
      packages + packages.flat_map {
        collect_packages.call(_1.fetch(:package_list, []))
      }
    }

    packages = collect_packages.call(body)

    packages_assoc       = packages.select { _1.fetch(:type) == "package" }.index_by { _1.fetch(:package_id) }
    package_groups_assoc = packages.select { _1.fetch(:type) == "package_group" }.index_by { _1.fetch(:package_group_uri) }

    package       = packages_assoc.fetch(package_id)
    package_group = package_groups_assoc.fetch(package.fetch(:parent_package_group_uri))

    {
      package_group: package_group.fetch(:package_group_id),
      env_package:   package.fetch(:env_package)
    }
  end
end
