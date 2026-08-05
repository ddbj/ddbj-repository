module DDBJRecord
  module V3
    DataFile = Data.define(
      :filename,
      :filetype,
      :checksum_method,
      :checksum,
      :unencrypted_checksum
    )
  end
end
