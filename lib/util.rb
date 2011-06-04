$:.unshift File.join(File.dirname(__FILE__),'.')

module CatalogTool

  module StringUtils

    def is_nil_or_empty?(s)
      if s.nil? || s.empty?
        return true
      end
      false
    end
    
    def is_same_string?(s1, s2)

      if is_nil_or_empty?(s1) and is_nil_or_empty?(s2)
        return true
      end

      if is_nil_or_empty?(s1) and ! is_nil_or_empty?(s2)
        return false
      end

      if is_nil_or_empty?(s2) and ! is_nil_or_empty?(s1)
        return false
      end
      s1 == s2
    end

    def is_same_string_nocase?(s1, s2)
      if is_nil_or_empty?(s1) and is_nil_or_empty?(s2)
        return true
      end

      if is_nil_or_empty?(s1) and ! is_nil_or_empty?(s2)
        return false
      end

      if is_nil_or_empty?(s2) and ! is_nil_or_empty?(s1)
        return false
      end
      s1.casecmp(s2) == 0
    end

    def get_boolean_string_from_relaxed_boolean_string(s)
      if is_nil_or_empty?(s)
        return "FALSE"
      else
        return s
      end
    end
    
    def is_same_string_boolean?(s1, s2)
      
      s1_sanity = get_boolean_string_from_relaxed_boolean_string(s1)
      s2_sanity = get_boolean_string_from_relaxed_boolean_string(s2)
      
      s1_sanity.casecmp(s2_sanity) == 0
    end


    def camel_to_underscore(s)
      res = nil
      if s
        res = s.gsub(/(.)([A-Z])/,'\1_\2').downcase
      end
      res
    end
  end
  


  module Enum

    class NameValuePair
      attr_reader :label, :value
      
      def initialize(label, value)
        @label = label
        @value = value
      end
      
      def first
        @label
      end
      
      def last
        @value
      end
    end

    def const_missing(key)
      @enum_hash[key]
    end
    
    def add_enum(key, value)
      @enum_hash ||= {}
      @enum_hash[key] = NameValuePair.new(value, key.to_s)
    end
    
    def each
      @enum_hash.values.sort { |v1, v2| v1.label <=> v2.label }.each do |k|
        yield(k)
      end
    end

    def collect
      @enum_hash.values.sort { |v1, v2| v1.label <=> v2.label }.collect do |k|
        yield(k)
      end
    end

    def each_with_index
      @enum_hash.values.sort { |v1, v2| v1.label <=> v2.label }.each_with_index do |k, i|
        yield(k, i)
      end
    end
    
    def enums
      @enum_hash.keys
    end
    
    def enum_values
      @enum_hash.values
    end
    
    def get_enum_hash
      @enum_hash
    end
    
    def find_by_key(key)
      @enum_hash[key.upcase.to_sym]
    end

    def size
      @enum_hash.keys.size
    end
  end

end

