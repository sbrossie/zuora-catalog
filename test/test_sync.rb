$:.unshift File.join(File.dirname(__FILE__),'.')

require "unit_tests_default"

module CatalogTool
  
  
  
  class TestCatalogSync < Test::Unit::TestCase

    #
    # Some private fields in zuora may be of type 'pick list'in whch case we don't know how to generate test value
    # so we ignore them. Not optimal but best we can do for a generic test framework
    #
    IGNORE_PRIVATE_PICK_LIST_VALUE = { 
      'Product' => nil,
      'ProductRatePlan' => ['Trial']
    }

    attr_reader :config, :zuora_client

    attr_accessor :p_id, :prp_id, :prpc_id, :prpct_id
    def setup
      super
      me = File.expand_path(__FILE__)
      pwd = File.dirname(me)
      config_file =  pwd + "/../conf/environment.yml"
      @config = Config.new("sandbox", config_file, @logger)
      @zuora_client = Zuora::API.new(@config)
      @p_id = nil 
      @prp_id = nil
      @prpc_id = nil
      @prpct_id = nil
    end

    def teardown
      if ! @prpc_id.nil?
        res = @zuora_client.delete_product_rate_plan_charge(@prpc_id)
        @logger.warn("Teardown : Failed to  delete prpc #{@prpc_id}") unless res[0][:success]
        @prpc_id = nil
      end
      if ! @prp_id.nil?
        res = @zuora_client.delete_product_rate_plan(@prp_id)
        @logger.warn("Teardown : Failed to delete prp #{@prp_id}") unless res[0][:success]
        @prpc_id = nil
      end
      if ! @p_id.nil?
        res = @zuora_client.delete_product(@p_id)
        @logger.info("Teardown : Failed to delete product #{@p_id}")  unless res[0][:success]
        @p_id = nil
      end 
    end
    

    def test_create_update_product
      
      @logger.info "Starting test_create_product"
      
      sku  = "t_catalog_prod"
      name  = "T Catalog - Prod"
      
      p_hash = build_private_fields('Product', @zuora_client.product_custom_fields, "crt")
      
      # Test creation
      res = @zuora_client.create_product(name, sku, p_hash)
      assert_equal(res[0][:success], true, "failed to create the test product")
      assert_not_nil(res[0][:id], "Could not find created product id")
      
      @p_id  = res[0][:id]
      
      z_product = @zuora_client.get_product_from_key(@product_key, sku)
      
      assert_not_nil(z_product, "returned a nil product result")
      assert_equal(z_product.size, 1, "Did not find exactly one product, but #{z_product.size} instead")
      assert_not_nil(z_product[0]['id'], "Could not find retrieved product id")
      assert_equal(z_product[0]['name'], name, "Found name = #{z_product[0]['name']} instead of #{name}")
      assert_private_fields(p_hash, z_product[0])
      
      # Test update now...
      p_hash = build_private_fields('Product', @zuora_client.product_custom_fields, "upd")
      
      res = @zuora_client.update_product(@p_id, p_hash)
      assert_equal(res[0][:success], true, "failed to update the test product")

      z_product = @zuora_client.get_product_from_key(@product_key,sku)
      assert_not_nil(z_product, "returned a nil product result")
      assert_equal(z_product.size, 1, "Did not find exactly one product, but #{z_product.size} instead")
      
      assert_private_fields(p_hash, z_product[0])
    end
    
    def test_create_update_prp
      
      
      @logger.info "Starting test_create_rp"
      
      sku  = "t_catalog_prod2"
      name  = "T Catalog - Prod2"

      res = @zuora_client.create_product(name, sku, nil)
      assert_equal(res[0][:success], true, "failed to create the test product")
      assert_not_nil(res[0][:id], "Could not find created product id")      
      
      @p_id = res[0][:id]

      # Creation
      z_product = @zuora_client.get_product_from_key(@product_key, sku)
      p_id = z_product[0]['id']
      name = "t_catalog_rp"
      start_date = z_product[0]['effectiveStartDate'] + 1
      end_date = z_product[0]['effectiveEndDate'] - 1
 
      rp_hash = build_private_fields('ProductRatePlan', @zuora_client.prp_custom_fields, "crt")
      
      res = @zuora_client.create_product_rate_plan(name, start_date, end_date, p_id,  rp_hash)
      
      assert_equal(res[0][:success], true, "failed to create the test rp")

      @prp_id = res[0][:id]
      
      z_prp =  @zuora_client.get_prp_from_key(@rp_key, name)
     
      assert_not_nil(z_prp, "returned a nil prp result")
      assert_equal(z_prp.size, 1, "Did not find exactly one prp, but #{z_prp.size} instead")
      assert_not_nil(z_prp[0]['id'], "Could not find retrieved product id")
      assert_equal(z_prp[0]['name'], name, "Found name = #{z_prp[0]['name']} instead of #{name}")

      assert_private_fields(rp_hash, z_prp[0])

      # Update fields
      name = "t_catalog_rp_update"
      rp_hash = build_private_fields('ProductRatePlan', @zuora_client.prp_custom_fields, "crt")      

      res = @zuora_client.update_product_rate_plan(@prp_id, name, rp_hash)
      assert_equal(res[0][:success], true, "failed to update the test rp")
      
      z_prp =  @zuora_client.get_prp_from_key(@rp_key, name)
     
      assert_not_nil(z_prp, "returned a nil prp result")
      assert_equal(z_prp.size, 1, "Did not find exactly one prp, but #{z_prp.size} instead")
      assert_not_nil(z_prp[0]['id'], "Could not find retrieved product id")
      assert_equal(z_prp[0]['name'], name, "Found name = #{z_prp[0]['name']} instead of #{name}")
      
      assert_private_fields(rp_hash, z_prp[0])      

    end
    

    def test_create_modify_prpc


      @logger.info "Starting test_create_rpc"

      sku  = "t_catalog_prod4"
      name  = "T Catalog - Prod4"

      res = @zuora_client.create_product(name, sku, nil)
      assert_equal(res[0][:success], true, "failed to create the test product")
      assert_not_nil(res[0][:id], "Could not find created product id")      

      @p_id = res[0][:id]

      z_product = @zuora_client.get_product_from_key(@product_key, sku)
      p_id = z_product[0]['id']
      name = "t_catalog_rp4"
      start_date = z_product[0]['effectiveStartDate'] + 1
      end_date = z_product[0]['effectiveEndDate'] - 1

      res = @zuora_client.create_product_rate_plan(name, start_date, end_date, p_id, nil)
      assert_equal(res[0][:success], true, "failed to create the test rp")

      @prp_id = res[0][:id]
      
      z_prp =  @zuora_client.get_prp_from_key(@rp_key, name)
      
      name = 'T Catalog - Prod 4 RPC'
      code = "whatever"
      billing_period = "Month"
      prp_id = z_prp[0]['id']
      charge_type = "Recurring"
      prices = [ 1, 2, 3, 4, 5, 6]
      
      res = @zuora_client.create_product_rate_plan_charge(name, code, billing_period, prp_id, charge_type, prices)
      
      assert_equal(res[0][:success], true, "failed to create the test prpc")
      assert_not_nil(res[0][:id], "Could not find created prpc")
      
      @prpc_id = res[0][:id]

      z_prpc = @zuora_client.get_prpc_from_prp_id(prp_id)
      assert_not_nil(z_prpc, "returned a nil prpc result")
      assert_equal(z_prpc.size, 1, "Did not find exactly one prp, but #{z_prpc.size} instead")
      assert_not_nil(z_prpc[0]['id'], "Could not find retrieved product id")
      assert_equal(z_prpc[0]['name'], name, "Found name = #{z_prpc[0]['name']} instead of #{name}")      
      assert_equal(z_prpc[0]['billingPeriod'], billing_period, "Found billing_period = #{z_prpc[0]['billingPeriod']} instead of #{billing_period}")            
      assert_equal(z_prpc[0]['chargeType'], charge_type, "Found charge_type = #{z_prpc[0]['chargeType']} instead of #{charge_type}")            
      
      z_prpct = @zuora_client.get_prpct_from_prpc_id(@prpc_id)
      assert_not_nil(z_prpct, "returned a nil prpct result")
      assert_equal(z_prpct.size, 6, "Did not find exactly 6 prpct, but #{z_prpct.size} instead")
      
      Currency.each_with_index do |c, i|
        
        cur_price = nil
        cur_currency = nil
        z_prpct.each do |e|
          if e['currency'] == c.value
            cur_price = e['price']
            cur_currency = c.value
            break
          end
        end
        
        assert_not_nil(cur_price)
        assert_equal(cur_price, prices[i], "Price for currency #{cur_currency} expected #{prices[i]}, got #{cur_price}")
      end
      
      @prpct_id = z_prpct.collect { |e| e['id'] }
      
      # Update
      name = 'T Catalog - Prod 4 RPC Update'
      code = "whatever update"
      billing_period = "Annual"
      res = @zuora_client.update_product_rate_plan_charge(@prpc_id, name, code, billing_period)
      assert_equal(res[0][:success], true, "failed to update the test prpc")
      
      z_prpc = @zuora_client.get_prpc_from_prp_id(prp_id)
      assert_not_nil(z_prpc, "returned a nil prpc result")
      assert_equal(z_prpc.size, 1, "Did not find exactly one prp, but #{z_prpc.size} instead")
      assert_not_nil(z_prpc[0]['id'], "Could not find retrieved product id")
      assert_equal(z_prpc[0]['name'], name, "Found name = #{z_prpc[0]['name']} instead of #{name}")      
      assert_equal(z_prpc[0]['billingPeriod'], billing_period, "Found billing_period = #{z_prpc[0]['billingPeriod']} instead of #{billing_period}")            
      assert_equal(z_prpc[0]['chargeType'], charge_type, "Found charge_type = #{z_prpc[0]['chargeType']} instead of #{charge_type}")      
      
      
      prices.collect! { |p| p * 2}
      Currency.each_with_index do |c, i|
        
        cur_prpct_id = nil
        z_prpct.each do |e|
           if e['currency'] == c.value
             cur_prpct_id = e['id']
             break
           end
         end   
         
         assert_not_nil(cur_prpct_id)
         res = @zuora_client.update_one_currency(cur_prpct_id, prices[i])
         assert_equal(res[0][:success], true, "failed to update currency #{c.value}")
      end
    
    
      z_prpct = @zuora_client.get_prpct_from_prpc_id(@prpc_id)
      assert_not_nil(z_prpct, "returned a nil prpct result")
      assert_equal(z_prpct.size, 6, "Did not find exactly 6 prpct, but #{z_prpct.size} instead")
      
      Currency.each_with_index do |c, i|
        
        cur_price = nil
        cur_currency = nil
        z_prpct.each do |e|
          if e['currency'] == c.value
            cur_price = e['price']
            cur_currency = c.value
            break
          end
        end
        
        assert_not_nil(cur_price)
        assert_equal(cur_price, prices[i], "Price for currency #{cur_currency} expected #{prices[i]}, got #{cur_price}")
      end
    end
    
    private
    
    
    def assert_private_fields(p_hash, res)
      p_hash.each do |k, v|
        kf = Zuora::API.format_private_field(k)
        assert_equal(res[kf], v, "Found #{k} = #{res[kf]} instead of #{v}")
      end
    end
    
    def build_private_fields(type, private_fields, suffix_value)

      result = {}
      ignore_list = IGNORE_PRIVATE_PICK_LIST_VALUE[type]
      
      private_fields.each do |f|
        ignore = false
        if ignore_list
          ignore_list.each do |i|
            if i == f
              ignore = true
              break
            end
          end
        end
        result[f] = "#{f}-#{suffix_value}" unless ignore
      end
      result
    end
    
  end

end