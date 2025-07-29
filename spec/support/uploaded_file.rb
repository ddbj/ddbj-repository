module UploadedFile
  def uploaded_file(name:, content: '')
    Rack::Test::UploadedFile.new(StringIO.new(content), original_filename: name)
  end
end
