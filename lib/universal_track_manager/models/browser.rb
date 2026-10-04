# frozen_string_literal: true

class UniversalTrackManager::Browser < ActiveRecord::Base
  self.table_name = "browsers"

  include UniversalTrackManager::ColumnLimits
  before_save :apply_column_limits
end
