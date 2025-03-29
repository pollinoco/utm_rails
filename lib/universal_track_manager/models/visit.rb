# frozen_string_literal: true

module UniversalTrackManager
  class Visit < ActiveRecord::Base
    self.table_name = 'visits'

    belongs_to :campaign, class_name: 'UniversalTrackManager::Campaign'
    belongs_to :browser, class_name: 'UniversalTrackManager::Browser'
    belongs_to :original_visit, optional: true, class_name: 'UniversalTrackManager::Visit'

    # class_name: "UniveralTrackManager::Visit",
    def matches_all_utms?(params)
      unless campaign
        # this visit has no campaign, which means all UTMs = null
        # if any of the UTMs are present, return false (they don't match null)
        return UniversalTrackManager.campaign_column_hashed.none? do |key|
          params[key].present?
        end
      end

      # NOTE: params are allowed to be missing
      UniversalTrackManager.campaign_column_hashed.each do |c|
        return false if (campaign[c] && (campaign[c] != params[c])) || (!campaign[c] && params[c])
      end
      true
    end

    def name
      "#{ip_v4_address} #{browser.name}"
    end
  end
end
