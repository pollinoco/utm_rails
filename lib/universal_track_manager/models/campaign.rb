# frozen_string_literal: true

require "zlib"

class UniversalTrackManager::Campaign < ActiveRecord::Base
  self.table_name = "campaigns"

  include UniversalTrackManager::ColumnLimits
  before_save :apply_column_limits

  # Busca por tienda + sha1. Sin store_id conserva el comportamiento de un solo tenant.
  def self.fetch_or_create!(sha1:, store_id:, gclid_present:, attributes:)
    finder = { sha1: sha1, gclid_present: gclid_present }
    finder[:store_id] = store_id unless store_id.nil?

    with_identity_lock(store_id, sha1) do
      find_by(finder) || create!(attributes)
    end
  end

  # Serializa el alta de la misma campaña dentro de la transacción.
  # El índice de sha1 no es único: sin este lock dos requests crean dos filas.
  def self.with_identity_lock(store_id, sha1)
    return yield unless connection.adapter_name.match?(/postg/i)

    transaction do
      store_key = store_id.to_i & 0x7fffffff
      sha_key = Zlib.crc32(sha1.to_s) & 0x7fffffff
      connection.execute(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?, ?)", store_key, sha_key ]))
      yield
    end
  end
  private_class_method :with_identity_lock
end
