module PathnameContain
  refine Pathname do
    def contain?(path)
      parent = self.expand_path
      child  = path.expand_path

      parent == child || child.to_s.start_with?("#{parent}/")
    end
  end
end
