# frozen_string_literal: true

module UniversalTrackManagerConcern
  extend ActiveSupport::Concern
  attr_accessor :visit_evicted

  included do
    before_action :track_visitor

    UniversalTrackManager.campaign_column_symbols.each do |s|
      define_method(s) do
        return nil unless UniversalTrackManager.track_utms?

        permitted_utm_params[s]
      end
    end
  end

  def permitted_utm_params
    params.permit(*UniversalTrackManager.campaign_column_symbols)
  end

  def hashed_utm_params
    params.permit(*UniversalTrackManager.campaign_column_hashed)
  end

  def ip_address
    return nil unless UniversalTrackManager.track_ips?

    request.ip
  end

  def user_agent
    return nil unless UniversalTrackManager.track_user_agent?

    request.user_agent && request.user_agent[0..254]
  end

  def now
    @now ||= Time.zone.now
  end

  def new_visitor
    if permitted_utm_params[:gclid].blank?
      if permitted_utm_params[:srsltid].blank?
        return nil unless permitted_utm_params[:utm_source].present?
      end
    end

    store_id = (@store.id if @store.present?)
    params = {
      first_pageload: now,
      last_pageload: now,
      ip_v4_address: ip_address,
      campaign: find_or_create_campaign_by_current,
      store_id:
    }

    if request.referer && !request.referer.include?(request.host) && UniversalTrackManager.track_http_referrer?
      params[:referer] = request.referer
    end

    params[:browser] = find_or_create_browser_by_current if request.user_agent
    visit = UniversalTrackManager::Visit.create!(params)
    session[:pze_visit_id] = visit.id
  end

  def track_visitor
    if session["pze_visit_id"]
      # existing visit
      begin
        existing_visit = UniversalTrackManager::Visit.find(session["pze_visit_id"])

        evict_visit!(existing_visit) if any_utm_params? && !existing_visit.matches_all_utms?(hashed_utm_params)

        evict_visit!(existing_visit) if existing_visit.ip_v4_address != ip_address

        evict_visit!(existing_visit) if existing_visit.browser && existing_visit.browser.name != user_agent

        if UniversalTrackManager.track_http_referrer?
          if existing_visit.referer == request.referer

          elsif request.referer && !request.referer.include?(request.host)
            evict_visit!(existing_visit)
          end
        end

        existing_visit.update_columns(last_pageload: Time.zone.now) unless @visit_evicted
      rescue ActiveRecord::RecordNotFound
        # this happens if the session table is cleared or if the record in the session
        # table points to a visit that has been cleared
        new_visitor
      end
    else
      new_visitor
    end
  end

  def any_utm_params?
    return false unless UniversalTrackManager.track_utms?

    UniversalTrackManager.campaign_column_hashed.any? do |key|
      params[key].present?
    end
  end

  def find_or_create_browser_by_current
    return nil unless UniversalTrackManager.track_user_agent?

    UniversalTrackManager::Browser.find_or_create_by(name: user_agent)
  end

  def find_or_create_campaign_by_current
    return nil unless UniversalTrackManager.track_utms?

    if permitted_utm_params[:gclid].blank?
      if permitted_utm_params[:srsltid].blank?
        return nil unless permitted_utm_params[:utm_source].present?
      end
    end

    gen_sha1 = gen_campaign_key(hashed_utm_params)

    store_id = (@store.id if @store.present?)

    request_campaign = request.url.split("?")[0]

    gclid_present = permitted_utm_params[:gclid].present?

    campaign = UniversalTrackManager::Campaign.find_by(sha1: gen_sha1,
                                                       gclid_present: gclid_present)

    campaign ||= UniversalTrackManager::Campaign.create(*permitted_utm_params.merge({
                                                                                      sha1: gen_sha1,
                                                                                      store_id:,
                                                                                      request_url: request_campaign,
                                                                                      gclid_present: gclid_present
                                                                                    }))
  end

  def gen_campaign_key(params)
    Digest::SHA1.hexdigest(params.keys.map(&:downcase).sort.map { |k| { "#{k}": params[k] } }.to_s)
  end

  def evict_visit!(old_visit)
    store_id = (@store.id if @store.present?)
    @visit_evicted = true
    params = {
      first_pageload: now,
      last_pageload: now,
      original_visit_id: old_visit.original_visit_id.nil? ? old_visit.id : old_visit.original_visit_id,
      count: old_visit.original_visit_id.nil? ? old_visit.count + 1 : 1,
      ip_v4_address: ip_address,
      campaign: find_or_create_campaign_by_current,
      store_id:
    }

    # fail silently if there is no user agent
    params[:browser] = find_or_create_browser_by_current if request.user_agent

    visit = UniversalTrackManager::Visit.create!(params)

    session[:pze_visit_id] = visit.id
  end
end
