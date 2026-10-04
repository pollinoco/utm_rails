# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require_relative "../lib/universal_track_manager/identity"

class IdentityTest < Minitest::Test
  def test_sha1_matches_the_historical_ruby_inspect
    params = { "utm_campaign" => "verano", "utm_source" => "google", "gclid" => nil }
    legacy = params.keys.map(&:downcase).sort.map { |key| { "#{key}": params[key] } }.to_s

    assert_equal Digest::SHA1.hexdigest(legacy), UniversalTrackManager::Identity.campaign_sha1(params)
    assert_equal "b988744244a420d16188974e02f2b2565e3cdf60", UniversalTrackManager::Identity.campaign_sha1(params)
  end

  def test_missing_param_still_matches_the_stored_campaign
    campaign = { utm_source: "google", utm_medium: "cpc", utm_campaign: "sale" }
    params = { "utm_source" => "google" }

    assert UniversalTrackManager::Identity.matches?(campaign, params, %i[utm_source utm_medium utm_campaign])
  end

  def test_changed_param_does_not_match
    campaign = { utm_source: "google", utm_medium: "cpc" }
    params = { "utm_source" => "facebook" }

    refute UniversalTrackManager::Identity.matches?(campaign, params, %i[utm_source utm_medium])
  end

  def test_new_value_on_an_empty_column_does_not_match
    campaign = { utm_source: "google", utm_medium: nil }
    params = { "utm_medium" => "email" }

    refute UniversalTrackManager::Identity.matches?(campaign, params, %i[utm_source utm_medium])
  end

  def test_nil_campaign_matches_only_when_no_utm_is_present
    columns = %i[utm_source utm_medium]

    assert UniversalTrackManager::Identity.matches?(nil, {}, columns)
    refute UniversalTrackManager::Identity.matches?(nil, { "utm_source" => "google" }, columns)
  end
end
