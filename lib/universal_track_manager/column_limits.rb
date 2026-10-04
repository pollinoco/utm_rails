# frozen_string_literal: true

module UniversalTrackManager
  # Recorta strings al limit de la columna para que un utm largo no tumbe el request.
  module ColumnLimits
    def apply_column_limits
      self.class.columns.each do |column|
        next unless column.limit

        value = self[column.name]
        next unless value.is_a?(String) && value.length > column.limit

        self[column.name] = value[0, column.limit]
      end
    end
  end
end
