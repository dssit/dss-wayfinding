class Floor < ApplicationRecord
  validates :title, uniqueness: true, presence: true
  validates :floor_number, uniqueness: true, presence: true
end
