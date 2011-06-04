$:.unshift File.join(File.dirname(__FILE__),'.')

require 'rubygems'
require "unit_tests_default"

module CatalogTool
  
  
  class TestCatalogValidation < Test::Unit::TestCase

    def test_missing_product
      @logger.info "Starting test_missing_product #{CSV_FILE_REF} -> #{CSV_FILE_PROD_MISS}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_PROD_MISS)
      do_assert_validation([1,0,0,0,0,0,0,0,0], res)
      assert_equal("bronze", res[:prods_missing][0].sku, "Found missing product #{res[:prods_missing][0].sku} instead of bronze")      
    end

    def test_new_product
      @logger.info "Starting test_new_product #{CSV_FILE_REF} -> #{CSV_FILE_PROD_ADD}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_PROD_ADD)
      do_assert_validation([0,0,0,0,1,0,0,0,0], res)
      assert_equal("bronze-extra", res[:prods_new][0].sku, "Found new product #{res[:prods_new][0].sku} instead of bronze-extra")
    end
    
    def test_prod_diff_ok
      @logger.info "Starting test_prod_diff_err #{CSV_FILE_REF} -> #{CSV_FILE_PROD_DIFF_OK}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_PROD_DIFF_OK)
      do_assert_validation([0,0,0,0,0,0,1,0,0], res)
      assert_equal("silver", res[:prods_diff_ok][0].sku, "Found product diff ok for #{res[:prods_diff_ok][0].sku} instead of silver")
    end

    def test_rp_diff_err
      @logger.info "Starting test_next_slug_diff #{CSV_FILE_REF} -> #{CSV_FILE_RP_DIFF_ERR}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_RP_DIFF_ERR)
      do_assert_validation([0,0,0,1,0,0,0,0,0], res)
      assert_equal("waffle-bronze-annual-trial", res[:rps_diff_err][0].slug, "Found rp diff err for #{res[:rps_diff_err][0].slug} instead of waffle-bronze-annual-trial")
    end

    def test_next_slug_diff
      @logger.info "Starting test_next_slug_diff #{CSV_FILE_REF} -> #{CSV_FILE_NEXT_SLUG_DIFF}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_NEXT_SLUG_DIFF)
      do_assert_validation([0,0,0,0,0,0,0,1,0], res)
      assert_equal("waffle-bronze-cafepress", res[:rps_diff_ok][0].slug, "Found missing nextSlug for #{res[:rps_diff_ok][0].slug} instead of waffle-bronze-cafepress")
    end
    
    def test_price_diff
      @logger.info "Starting test_price_diff #{CSV_FILE_REF} -> #{CSV_FILE_PRICE_DIFF}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_PRICE_DIFF)
      do_assert_validation([0,0,0,0,0,0,0,0,1], res)
      assert_equal("waffle-bronze-monthly", res[:prices_update][0].slug, "Found price diff #{res[:prices_update][0].slug} instead of waffle-bronze-monthly")
    end

    def test_new_rp
      @logger.info "Starting test_new_rp #{CSV_FILE_REF} -> #{CSV_FILE_RP_ADD}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_RP_ADD)
      do_assert_validation([0,0,0,0,0,1,0,0,0], res)
      assert_equal("waffle-bronze-monthly-add", res[:rps_new][0].slug, "Found new rp #{res[:rps_new][0].slug} instead of waffle-bronze-monthly-add")
    end

    def test_missing_rp
      @logger.info "Starting test_missing_rp #{CSV_FILE_REF} -> #{CSV_FILE_RP_MISS}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_RP_MISS)
      do_assert_validation([0,1,0,0,0,0,0,0,0], res)
      assert_equal("waffle-bronze-annual", res[:rps_missing][0].slug, "Found new rp #{res[:rps_missing][0].slug} instead of waffle-bronze-annual")
    end

    def test_wrong_trial
      @logger.info "Starting test_wrong_trial #{CSV_FILE_REF} -> #{CSV_FILE_TRIAL_DIFF}"
      res = run_validation_for(CSV_FILE_REF, CSV_FILE_TRIAL_DIFF)
      do_assert_validation([0,0,0,0,0,0,0,2,0], res)
      assert_equal("waffle-bronze-monthly-trial", res[:rps_diff_ok][0].slug, "Found new rp #{res[:rps_diff_ok][0].slug} instead of  waffle-bronze-monthly-trial")      
      assert_equal("waffle-bronze-annual-trial", res[:rps_diff_ok][1].slug, "Found new rp #{res[:rps_diff_ok][1].slug} instead of waffle-bronze-annual-trial")
    end


    private
    
    def run_validation_for(csv_ref_file, csv_check_file)
      
      csv_ref = CSVCatalogReader.new(@logger, SANITY_VALIDATION, Zuora.private_fields, csv_ref_file)
      csv_prod_miss = CSVCatalogReader.new(@logger, SANITY_VALIDATION, Zuora.private_fields, csv_check_file)      
      validator = Validator.new(@logger)
      validator.cross_validation_from_csvs(csv_ref, csv_prod_miss)
    end
    
    def do_assert_validation(exp, res)
      assert_equal(exp[0], res[:prods_missing].size, "Expected #{exp[0]} missing product, got #{res[:prods_missing].size}")
      assert_equal(exp[1], res[:rps_missing].size, "Expected #{exp[1]} missing rps, got #{res[:rps_missing].size}")         
      assert_equal(exp[2], res[:prods_diff_err].size, "Expected #{exp[2]} products error diff, got #{res[:prods_diff_err].size}")               
      assert_equal(exp[3], res[:rps_diff_err].size, "Expected #{exp[3]} rps error diff, got #{res[:rps_diff_err].size}")               
      assert_equal(exp[4], res[:prods_new].size, "Expected #{exp[4]} new products, got #{res[:prods_new].size}")               
      assert_equal(exp[5], res[:rps_new].size, "Expected #{exp[5]} new products, got #{res[:rps_new].size}")               
      assert_equal(exp[6], res[:prods_diff_ok].size, "Expected #{exp[6]} products ok diff, got #{res[:prods_diff_ok].size}")               
      assert_equal(exp[7], res[:rps_diff_ok].size, "Expected #{exp[7]} rps ok diff, got #{res[:rps_diff_ok].size}")               
      assert_equal(exp[8], res[:prices_update].size, "Expected #{exp[8]} prices update, got #{res[:prices_update].size}")               
    end
    
    
  end
end