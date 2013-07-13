require 'json'
require 'rest-client'
require 'active_support/core_ext/object/blank'
require 'kaminari/models/array_extension' if defined?(Kaminari)

module Waistband
  class Query

    attr_accessor :page, :page_size

    def initialize(index, search_term, options = {})
      @index        = index
      @search_term  = search_term
      @wildcards    = []
      @fields       = []
      @ranges       = []
      @sorts        = []
      @terms        = {}
      @page         = (options[:page] || 1).to_i
      @page_size    = (options[:page_size] || 20).to_i
    end

    def paginated_results
      return Kaminari.paginate_array(results, total_count: total_results).page(@page).per(@page_size) if defined?(Kaminari)
      raise "Please include the `kaminari` gem to use this method!"
    end

    def results
      hits.map do |hit|
        Waistband::QueryResult.new(hit)
      end
    end

    def hits
      execute!['hits']['hits'] rescue []
    end

    def total_results
      execute!['hits']['total'] rescue 0
    end

    def add_match(field)
      @match = field
    end

    def add_fields(*fields)
      @fields |= fields
      @fields = @fields.compact.uniq
    end
    alias :add_field :add_fields

    def add_wildcard(wildcard, value)
      @wildcards << {
        wildcard: wildcard,
        value: value
      }
    end

    def add_range(field, min, max)
      @ranges << {
        field: field,
        min: min,
        max: max
      }
    end

    def add_terms(key, words)
      @terms[key] ||= {
        keywords: []
      }
      @terms[key][:keywords] += words.gsub(/ +/, ' ').strip.split(' ').uniq
    end
    alias :add_term :add_terms

    def add_sort(key, ord)
      @sorts << {
        key: key,
        ord: ord
      }
    end

    private

      def execute!
        @executed ||= JSON.parse(RestClient.post(url, to_hash.to_json))
      end

      def url
        "#{Waistband.config.hostname}/#{@index}/_search"
      end

      def to_hash
        {
          query: {
            bool: {
              must: must_to_hash,
              must_not: [],
              should: []
            }
          },
          from: from,
          size: @page_size,
          sort: sort_to_hash
        }
      end

      def sort_to_hash
        sort = []

        @sorts.each do |s|
          sort << {s[:key] => s[:ord]}
        end

        sort << '_score'

        sort
      end

      def must_to_hash
        must = []

        must << {
          multi_match: {
            query: @search_term,
            fields: @fields
          }
        } if @fields.any?

        @wildcards.each do |wc|
          must << {
            wildcard: {
              wc[:wildcard] => wc[:value]
            }
          }
        end

        @ranges.each do |range|
          must << {
            range: {
              range[:field] => {
                lte: range[:max],
                gte: range[:min],
              }
            }
          }
        end

        must << {
          match: {
            @match => @search_term
          }
        } if @match.present?

        terms.each do |term|
          must << term
        end

        must
      end

      def terms
        @terms.map do |key, term|
          {
            terms: {
              key.to_sym => term[:keywords]
            }
          }
        end
      end

      def from
        f = @page_size * (@page - 1)
        f -= 1 if f > 0
        f
      end

    # /private

  end
end
