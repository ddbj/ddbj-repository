class User < ApplicationRecord
  def self.generate_api_key
    SecureRandom.base58(32)
  end

  has_many :validations, dependent: :destroy

  has_many :submissions, through: :validations
  has_many :accessions,  through: :submissions

  before_create do |user|
    user.api_key ||= self.class.generate_api_key
  end

  def token
    JWT.encode({user_id: id}, Rails.application.secret_key_base, 'HS512')
  end
end
