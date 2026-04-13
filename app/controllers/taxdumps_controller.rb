class TaxdumpsController < ApplicationController
  def show
    @names_count = Taxdump::Name.count
    @nodes_count = Taxdump::Node.count
  end

  def create
    unless current_user.admin?
      return render json: {error: 'Forbidden'}, status: :forbidden
    end

    request.env['puma.mark_as_io_bound']&.call

    path = Rails.root.join('storage/taxdump.tar.gz')

    unless path.exist?
      return render json: {error: 'storage/taxdump.tar.gz not found'}, status: :unprocessable_entity
    end

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

    show
  end
end
