class User < ApplicationRecord
  def self.generate_api_key
    SecureRandom.base58(32)
  end

  has_many :submission_requests

  has_many :submissions,        through: :submission_requests
  has_many :submission_updates, through: :submissions, source: :updates

  before_create do |user|
    user.api_key ||= self.class.generate_api_key
  end

  def token
    JWT.encode({user_id: id}, Rails.application.secret_key_base, 'HS512')
  end
end
