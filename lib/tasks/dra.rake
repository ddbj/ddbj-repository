namespace :dra do
  # Reads a run's reads as the check before accessions will (DRA::ReadCheck),
  # from files a user has uploaded and not yet assigned — picked by name, as a
  # record will pick them. For trying the loader on real reads until
  # submissions reach it themselves.
  #
  #   bin/rails 'dra:check_reads[alice,ILLUMINA,run1_R1.fastq.gz,run1_R2.fastq.gz]'
  desc "Read a user's uploaded reads with SRA Toolkit's loader"
  task :check_reads, %i[uid platform] => :environment do |_, args|
    user  = User.find_by!(uid: args[:uid])
    names = args.extras

    abort 'Name the files to read.' if names.empty?

    blobs = names.map {|name|
      user.unassigned_files.blobs.find_by(filename: name) or abort "#{args[:uid]} has no unassigned file named #{name}."
    }

    result = DRA::ReadCheck.call(files: blobs, platform: args[:platform])

    puts result.output

    # Taken, as D-way took it, can still have dropped records the loader
    # could not read.
    verdict =
      if !result.ok?
        'Refused.'
      elsif result.errors.any?
        "Read, with #{result.errors.size} error line(s) above: records may have been dropped."
      else
        'Read.'
      end

    puts verdict
  end
end
