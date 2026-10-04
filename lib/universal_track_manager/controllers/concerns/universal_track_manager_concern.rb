# frozen_string_literal: true

require "digest"
require "uri"

# Tracking de campañas. La sesión sigue exponiendo "pze_visit_id" (la lee el carrito).
# "pze_visit_by_store" guarda la visita de cada tienda para no mezclar tenants
# cuando varias tiendas comparten la cookie.
module UniversalTrackManagerConcern
  extend ActiveSupport::Concern

  SESSION_VISIT_ID = "pze_visit_id"
  SESSION_BUCKET = "pze_visit_by_store"
  SESSION_BROWSER_ID = "pze_browser_id"
  SESSION_BROWSER_FP = "pze_browser_fp"
  MAX_STORED_STORES = 30
  # utm_source sigue siendo la señal clásica. Los click ids cubren anuncios sin UTM.
  # fbclid solo entra si está en campaign_columns (si no, permit lo deja fuera).
  SIGNAL_PARAMS = %i[utm_source gclid srsltid fbclid].freeze

  attr_accessor :visit_evicted

  included do
    before_action :track_visitor

    UniversalTrackManager.campaign_column_symbols.each do |column|
      define_method(column) do
        return nil unless UniversalTrackManager.track_utms?

        permitted_utm_params[column]
      end
    end
  end

  def permitted_utm_params
    @permitted_utm_params ||= params.permit(*UniversalTrackManager.campaign_column_symbols)
  end

  def hashed_utm_params
    @hashed_utm_params ||= params.permit(*UniversalTrackManager.campaign_column_hashed)
  end

  def ip_address
    return nil unless UniversalTrackManager.track_ips?

    request.ip
  end

  def user_agent
    return nil unless UniversalTrackManager.track_user_agent?
    return nil if request.user_agent.blank?

    request.user_agent[0, 255]
  end

  def now
    @now ||= Time.zone.now
  end

  def any_utm_params?
    return @any_utm_params if defined?(@any_utm_params)
    return @any_utm_params = false unless UniversalTrackManager.track_utms?

    @any_utm_params = UniversalTrackManager.campaign_column_hashed.any? do |key|
      params[key].present?
    end
  end

  def track_visitor
    return unless tracking_active?

    reconcile_session_pointer!
    return if fast_track?

    visit_id = visit_id_for_current_store
    if visit_id
      track_existing_visit(visit_id)
    elsif campaign_signal?
      new_visitor
    end
  rescue StandardError => error
    Rails.logger.error("[UniversalTrackManager] #{error.class}: #{error.message}")
    raise unless Rails.env.production?
  end

  def new_visitor
    return nil unless campaign_signal?

    campaign = find_or_create_campaign_by_current
    return nil if campaign.nil? || !campaign.persisted?

    referer = external_referer_url
    visit = UniversalTrackManager::Visit.create!(
      first_pageload: now,
      last_pageload: now,
      ip_v4_address: ip_address,
      campaign: campaign,
      store_id: current_store_id,
      referer: referer,
      browser: find_or_create_browser_by_current
    )
    remember_visit!(visit, referer)
    visit
  end

  def find_or_create_browser_by_current
    return nil unless UniversalTrackManager.track_user_agent?

    agent = user_agent
    return nil if agent.blank?

    fingerprint = Digest::SHA1.hexdigest(agent)
    cached_id = session[SESSION_BROWSER_ID]
    if session[SESSION_BROWSER_FP] == fingerprint && cached_id.present?
      cached = UniversalTrackManager::Browser.find_by(id: cached_id)
      return cached if cached&.name == agent
    end

    browser = UniversalTrackManager::Browser.find_or_create_by!(name: agent)
    session[SESSION_BROWSER_ID] = browser.id
    session[SESSION_BROWSER_FP] = fingerprint
    browser
  end

  def find_or_create_campaign_by_current
    return nil unless campaign_signal?

    utm = permitted_utm_params
    sha1 = gen_campaign_key(hashed_utm_params)
    store_id = current_store_id
    gclid_present = utm[:gclid].present?

    UniversalTrackManager::Campaign.fetch_or_create!(
      sha1: sha1,
      store_id: store_id,
      gclid_present: gclid_present,
      attributes: utm.to_h.merge(
        "sha1" => sha1,
        "store_id" => store_id,
        "request_url" => request.url.to_s.split("?", 2).first,
        "gclid_present" => gclid_present
      )
    )
  end

  def gen_campaign_key(utm_params)
    UniversalTrackManager::Identity.campaign_sha1(utm_params)
  end

  def evict_visit!(old_visit)
    referer = external_referer_url
    campaign = find_or_create_campaign_by_current
    campaign ||= old_visit.campaign if campaign_for_current_store?(old_visit.campaign)
    return nil if campaign.nil?

    @visit_evicted = true

    root_id = old_visit.original_visit_id.nil? ? old_visit.id : old_visit.original_visit_id
    count = old_visit.original_visit_id.nil? ? old_visit.count.to_i + 1 : 1
    visit = UniversalTrackManager::Visit.create!(
      first_pageload: now,
      last_pageload: now,
      original_visit_id: root_id,
      count: count,
      ip_v4_address: ip_address,
      campaign: campaign,
      store_id: current_store_id,
      referer: referer,
      browser: find_or_create_browser_by_current
    )
    remember_visit!(visit, referer)
    visit
  end

  private

  def tracking_active?
    UniversalTrackManager.track_utms? || UniversalTrackManager.track_ips? || UniversalTrackManager.track_user_agent?
  end

  def campaign_signal?
    return @campaign_signal if defined?(@campaign_signal)
    return @campaign_signal = false unless UniversalTrackManager.track_utms?

    utm = permitted_utm_params
    @campaign_signal = SIGNAL_PARAMS.any? { |key| utm[key].present? }
  end

  def current_store_id
    return @utm_store_id if defined?(@utm_store_id)

    @utm_store_id = @store.id if defined?(@store) && @store.present?
  end

  # Si borraron pze_visit_id (limpiar sesión), no restaurar la visita desde el bucket.
  # Si el puntero es de otra tienda, cambiarlo al de la tienda actual o quitarlo.
  def reconcile_session_pointer!
    entry = raw_bucket
    pointer = session[SESSION_VISIT_ID]

    if pointer.blank?
      drop_current_store_bucket! if entry
      return
    end

    return unless pointer_belongs_to_other_store?(pointer)

    if entry && entry[0].to_i != pointer.to_i
      session[SESSION_VISIT_ID] = entry[0]
    elsif entry.nil?
      session.delete(SESSION_VISIT_ID)
    end
  end

  def fast_track?
    entry = raw_bucket
    return false unless entry
    return false unless session[SESSION_VISIT_ID].to_i == entry[0].to_i
    return false unless entry[1] == request_fingerprint
    return false if any_utm_params?
    return false if conflicting_referer?(entry[3])

    touch_visit_id(entry[0], entry[2])
    true
  end

  def visit_id_for_current_store
    entry = raw_bucket
    return entry[0] if entry && session[SESSION_VISIT_ID].to_i == entry[0].to_i

    buckets = session[SESSION_BUCKET]
    return nil if buckets.is_a?(Hash) && buckets.any?

    session[SESSION_VISIT_ID]
  end

  def track_existing_visit(visit_id)
    visit = load_visit(visit_id)
    unless visit && same_store?(visit)
      session.delete(SESSION_VISIT_ID)
      new_visitor if campaign_signal?
      return
    end

    if should_evict?(visit)
      # nil: la campaña anterior es de otra tienda y no hay UTM nuevo. Se conserva esta visita.
      return if evict_visit!(visit)
    end

    touch_loaded_visit(visit)
    remember_visit!(visit, visit.referer)
  end

  def load_visit(visit_id)
    scope = UniversalTrackManager::Visit.all
    scope = scope.includes(:campaign) if any_utm_params?
    scope = scope.includes(:browser) if UniversalTrackManager.track_user_agent?
    scope.find_by(id: visit_id)
  end

  def same_store?(visit)
    return true if current_store_id.nil?

    visit.store_id.to_i == current_store_id.to_i
  end

  def campaign_for_current_store?(campaign)
    return false if campaign.nil?
    return true if current_store_id.nil? || campaign.store_id.nil?

    campaign.store_id.to_i == current_store_id.to_i
  end

  def should_evict?(visit)
    return true if any_utm_params? && !visit.matches_all_utms?(hashed_utm_params)
    return true if UniversalTrackManager.track_ips? && visit.ip_v4_address != ip_address
    if UniversalTrackManager.track_user_agent? && visit.browser && visit.browser.name != user_agent
      return true
    end

    referer_evict?(visit)
  end

  def touch_loaded_visit(visit)
    return if visit.last_pageload.present? && fresh_touch?(visit.last_pageload.to_i)

    visit.update_columns(last_pageload: now)
  end

  def touch_visit_id(visit_id, touched_at)
    return if fresh_touch?(touched_at)

    scope = UniversalTrackManager::Visit.where(id: visit_id)
    scope = scope.where(store_id: current_store_id) if current_store_id
    if scope.update_all(last_pageload: now).zero?
      drop_current_store_bucket!
      session.delete(SESSION_VISIT_ID)
      new_visitor if campaign_signal?
    else
      refresh_bucket_touch(visit_id)
    end
  end

  def fresh_touch?(touched_at)
    interval = UniversalTrackManager.touch_interval
    return false if interval <= 0

    touched_at.to_i > now.to_i - interval
  end

  def remember_visit!(visit, referer_url)
    session[SESSION_VISIT_ID] = visit.id
    buckets = session[SESSION_BUCKET]
    buckets = buckets.is_a?(Hash) ? buckets.dup : {}
    buckets[current_store_id.to_s] = [
      visit.id,
      request_fingerprint,
      now.to_i,
      referer_digest(referer_url)
    ]
    if buckets.size > MAX_STORED_STORES
      buckets = buckets.sort_by { |_key, entry| entry[2].to_i }.last(MAX_STORED_STORES).to_h
    end
    session[SESSION_BUCKET] = buckets
  end

  def refresh_bucket_touch(visit_id)
    buckets = session[SESSION_BUCKET]
    return unless buckets.is_a?(Hash)

    entry = buckets[current_store_id.to_s]
    return unless entry.is_a?(Array) && entry[0].to_i == visit_id.to_i

    updated = buckets.dup
    updated[current_store_id.to_s] = [ entry[0], entry[1], now.to_i, entry[3] ]
    session[SESSION_BUCKET] = updated
  end

  def raw_bucket
    buckets = session[SESSION_BUCKET]
    return nil unless buckets.is_a?(Hash)

    entry = buckets[current_store_id.to_s]
    entry if entry.is_a?(Array) && entry.size >= 4
  end

  def drop_current_store_bucket!
    buckets = session[SESSION_BUCKET]
    return unless buckets.is_a?(Hash) && buckets.key?(current_store_id.to_s)

    updated = buckets.dup
    updated.delete(current_store_id.to_s)
    session[SESSION_BUCKET] = updated
  end

  def pointer_belongs_to_other_store?(pointer)
    buckets = session[SESSION_BUCKET]
    return false unless buckets.is_a?(Hash)

    store_key = current_store_id.to_s
    buckets.any? do |key, entry|
      key != store_key && entry.is_a?(Array) && entry[0].to_i == pointer.to_i
    end
  end

  def request_fingerprint
    @request_fingerprint ||= begin
      parts = [ current_store_id.to_s ]
      parts << ip_address.to_s if UniversalTrackManager.track_ips?
      parts << user_agent.to_s if UniversalTrackManager.track_user_agent?
      Digest::SHA1.hexdigest(parts.join("\u001f"))
    end
  end

  def external_referer_url
    return @external_referer_url if defined?(@external_referer_url)
    return @external_referer_url = nil unless UniversalTrackManager.track_http_referrer?

    ref = request.referer
    if ref.blank?
      @external_referer_url = nil
    else
      host = referer_host(ref)
      @external_referer_url = host.nil? || same_site_host?(host) ? nil : ref
    end
  end

  def referer_host(url)
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end

  def same_site_host?(other_host)
    host = request.host.to_s.downcase
    other = other_host.to_s.downcase
    return false if host.empty? || other.empty?

    other == host || other.end_with?(".#{host}") || host.end_with?(".#{other}")
  end

  def conflicting_referer?(stored_digest)
    incoming = external_referer_url
    return false if incoming.blank?

    referer_digest(incoming) != stored_digest
  end

  def referer_evict?(visit)
    incoming = external_referer_url
    return false if incoming.blank?

    visit.referer != incoming
  end

  def referer_digest(url)
    return nil if url.blank?

    Digest::SHA1.hexdigest(url)
  end
end
