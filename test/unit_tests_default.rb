$:.unshift File.join(File.dirname(__FILE__),'../lib')

require 'rubygems'

require 'test/unit'

require 'rubygems'
require 'logger'

require "csv"
require "catalog"
require "zuora"
require "validation"
require "config"


module CatalogTool



  class Test::Unit::TestCase

    THIS_FILE = File.expand_path(__FILE__)
    PWD = File.dirname(THIS_FILE)
    TEST_DATA = PWD + "/data"
    SANITY_VALIDATION = PWD + "/../lib/sanity/sanity.rb"


    CSV_FILE_REF = "#{TEST_DATA}/catalog_ref.csv"
    CSV_FILE_NEXT_SLUG_DIFF = "#{TEST_DATA}/catalog_ref_nextslugdiff.csv"
    CSV_FILE_PRICE_DIFF = "#{TEST_DATA}/catalog_ref_pricediff.csv"
    CSV_FILE_PROD_MISS = "#{TEST_DATA}/catalog_ref_prodmiss.csv"
    CSV_FILE_RP_ADD = "#{TEST_DATA}/catalog_ref_rpadd.csv"
    CSV_FILE_RP_MISS = "#{TEST_DATA}/catalog_ref_rpmiss.csv"
    CSV_FILE_TRIAL_DIFF = "#{TEST_DATA}/catalog_ref_trialdiff.csv"
    CSV_FILE_PROD_ADD = "#{TEST_DATA}/catalog_ref_prodadd.csv"
    CSV_FILE_PROD_DIFF_OK = "#{TEST_DATA}/catalog_ref_proddiffok.csv" 
    CSV_FILE_RP_DIFF_ERR = "#{TEST_DATA}/catalog_ref_rpdifferr.csv"
    
    attr_reader :logger, :product_key, :rp_key

    #def initialize(test_method_name)
    #  @logger = Logger.new(STDOUT) 
    #  super(test_method_name)
    #end

    def setup
      @logger = Logger.new(STDOUT) 
      @logger.level = Logger::DEBUG
      #$ZUORA_VERBOSE = true
      setup_keys
    end
    
    def setup_keys
      @product_key = CSVProduct::DEFAULT_KEY_FIELD_PRODUCT.sub(/^\w/) { |i| i.upcase }
      @rp_key = CSVRP::DEFAULT_KEY_FIELD_RP.sub(/^\w/) { |i| i.upcase }
    end


  end
end



