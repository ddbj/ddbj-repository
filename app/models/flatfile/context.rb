# frozen_string_literal: true

module Flatfile
  Context = Data.define(
    :root
  ) {
    include Helper

    delegate :record, :entries, to: :root
  }
end
