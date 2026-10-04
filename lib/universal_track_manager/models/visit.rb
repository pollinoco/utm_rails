# frozen_string_literal: true

module UniversalTrackManager
  class Visit < ActiveRecord::Base
    self.table_name = "visits"

    include UniversalTrackManager::ColumnLimits
    before_save :apply_column_limits

    # Opcionales: la app ya los declara así y un request sin user agent no debe fallar.
    belongs_to :campaign, class_name: "UniversalTrackManager::Campaign", optional: true
    belongs_to :browser, class_name: "UniversalTrackManager::Browser", optional: true
    belongs_to :original_visit, optional: true, class_name: "UniversalTrackManager::Visit"

    def matches_all_utms?(params)
      UniversalTrackManager::Identity.matches?(campaign, params, UniversalTrackManager.campaign_column_hashed)
    end

    def name
      "#{ip_v4_address} #{browser&.name}"
    end
  end
end
