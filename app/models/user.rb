class User < ApplicationRecord
  def self.generate_api_key
    SecureRandom.base58(32)
  end

  has_many :validations
  has_many :submissions, through: :validations

  before_create do |user|
    user.api_key ||= self.class.generate_api_key
  end
end
