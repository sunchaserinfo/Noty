class User < ActiveRecord::Base
  validates_uniqueness_of :jid
  has_many :notes, :dependent => :destroy
end
