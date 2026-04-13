class LoadTaxdumpJob < ApplicationJob
  def self.loading?
    SolidQueue::Job
      .where(class_name: name)
      .where(finished_at: nil)
      .where.not(id: SolidQueue::FailedExecution.select(:job_id))
      .exists?
  end

  def perform
    path = Rails.root.join('storage/taxdump.tar.gz')

    Dir.mktmpdir do |tmp|
      system 'tar', '-xzf', path.to_s, '-C', tmp, exception: true

      Taxdump::Record.connection.truncate Taxdump::Name.table_name
      Taxdump::Record.connection.truncate Taxdump::Node.table_name

      IO.foreach("#{tmp}/names.dmp", chomp: true).each_slice 10_000 do |lines|
        Taxdump::Name.insert_all lines.map {|line|
          tax_id, name_txt, name_class = line.split('|').values_at(0, 1, 3).map(&:strip)

          {
            tax_id:     tax_id.to_i,
            name_txt:,
            name_class:
          }
        }
      end

      IO.foreach("#{tmp}/nodes.dmp", chomp: true).each_slice 10_000 do |lines|
        Taxdump::Node.insert_all lines.map {|line|
          tax_id, parent_tax_id, rank, hidden_flag = line.split('|').values_at(0, 1, 2, 10).map(&:strip)

          {
            tax_id:        tax_id.to_i,
            parent_tax_id: parent_tax_id.to_i,
            rank:,
            hidden_flag:   hidden_flag == '1'
          }
        }
      end
    end
  end
end
