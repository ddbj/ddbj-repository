class User < ApplicationRecord
  has_many :validations
  has_many :submissions, through: :validations

  before_create do |user|
    user.api_key ||= self.class.generate_api_key
  end

  def self.generate_api_key
    "ddbj_repository_#{Base62.encode(SecureRandom.random_number(2 ** 256))}"
  end
end
