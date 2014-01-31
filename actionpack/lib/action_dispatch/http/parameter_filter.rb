module ActionDispatch
  module Http
    class ParameterFilter
      FILTERED = '[FILTERED]'.freeze # :nodoc:

      def initialize(filters = [])
        @filters = filters
      end

      def filter(params)
        compiled_filter.call(params)
      end

    private

      def compiled_filter
        @compiled_filter ||= CompiledFilter.compile(@filters)
      end

      class CompiledFilter # :nodoc:
        def self.compile(filters)
          return lambda { |params| params.dup } if filters.empty?

          strings, regexps, blocks = [], [], []

          filters.each do |item|
            case item
            when Proc
              blocks << item
            when Regexp
              regexps << item
            else
              strings << Regexp.escape(item.to_s)
            end
          end

          deep_regexps, regexps = regexps.partition { |r| r.to_s.include?("\\.") }
          deep_strings, strings = strings.partition { |s| s.include?("\\.") }

          regexps << Regexp.new(strings.join('|'), true) unless strings.empty?
          deep_regexps << Regexp.new(deep_strings.join('|'), true) unless deep_strings.empty?

          new regexps, deep_regexps, blocks
        end

        attr_reader :regexps, :deep_regexps, :blocks

        def initialize(regexps, deep_regexps, blocks)
          @regexps = regexps
          @deep_regexps = deep_regexps.any? ? deep_regexps : nil
          @blocks  = blocks
        end

        def call(original_params, parents = [])
          filtered_params = {}

          original_params.each do |key, value|
            if regexps.any? { |r| key =~ r }
              value = FILTERED
            elsif deep_regexps && (joined = (parents + [key]).join('.')) && deep_regexps.any? { |r| joined =~ r }
              value = FILTERED
            elsif value.is_a?(Hash)
              value = call(value, (parents + [key]))
            elsif value.is_a?(Array)
              value = value.map { |v| v.is_a?(Hash) ? call(v, (parents + [key])) : v }
            elsif blocks.any?
              key = key.dup
              value = value.dup if value.duplicable?
              blocks.each { |b| b.call(key, value) }
            end

            filtered_params[key] = value
          end

          filtered_params
        end
      end
    end
  end
end
