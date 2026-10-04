# frozen_string_literal: true

require "digest"

module UniversalTrackManager
  # Identidad de campaña y comparación de UTMs, sin ActiveRecord.
  #
  # El SHA1 tiene que seguir saliendo igual que en las filas ya guardadas:
  # es el inspect de Ruby de un array de hashes con claves símbolo.
  module Identity
    module_function

    def campaign_sha1(params)
      source = params.keys.map { |key| key.to_s.downcase }.sort.map do |key|
        { "#{key}": params[key] }
      end.to_s

      Digest::SHA1.hexdigest(source)
    end

    # Una columna ausente en el request no rompe la visita. Solo cuenta un
    # valor presente que no coincide con el guardado (o que el guardado no tiene).
    def matches?(campaign, params, columns)
      if campaign.nil?
        return columns.none? { |key| present?(param_value(params, key)) }
      end

      columns.each do |key|
        incoming = param_value(params, key)
        next unless present?(incoming)

        return false if campaign_value(campaign, key).to_s != incoming.to_s
      end
      true
    end

    def param_value(params, key)
      return params[key] if params.respond_to?(:key?) && params.key?(key)
      return params[key.to_s] if params.respond_to?(:key?) && params.key?(key.to_s)

      nil
    end

    def campaign_value(record, key)
      if record.is_a?(Hash)
        return record[key] if record.key?(key)
        return record[key.to_s] if record.key?(key.to_s)

        return nil
      end

      record[key]
    end

    def present?(value)
      return false if value.nil?
      return !value.strip.empty? if value.is_a?(String)
      return !value.empty? if value.respond_to?(:empty?)

      true
    end
  end
end
