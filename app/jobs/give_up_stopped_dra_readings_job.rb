# See DDBJValidatorCheck.give_up_stopped_readings.
class GiveUpStoppedDRAReadingsJob < ApplicationJob
  def perform = DDBJValidatorCheck.give_up_stopped_readings
end
