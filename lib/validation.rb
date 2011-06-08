$:.unshift File.join(File.dirname(__FILE__),'.')

require 'rubygems'
require 'logger'


module CatalogTool

  
  # Should not happen
  class ValidationInternalException < Exception
    
  end
  
  # Validation error
  class ValidationException < Exception
    
  end

  
  class Validator

    attr_reader :logger

    attr_accessor :missing_prods_zuora, :missing_prps_zuora, :modified_prices_zuora

    def initialize(logger)
      
      @logger = logger

      @missing_prods_zuora = []
      @missing_prps_zuora = []
      @modified_prices_zuora = []
     end
    

     def sync_from_diff(hash_diff, zuora_client, pause_between_change)

       begin
         
         if hash_diff.nil? || hash_diff.size == 0
           @logger.info("Nothing to sync from diffs")
           return
         end

         sanity_check(hash_diff)

         # Abort current method if does not type 'y' between each modification
         wait_for_answer_proc = Proc.new do |msg|
           if pause_between_change
             puts "\n#{msg} [y/n]?"
             ans=gets
             ansf=ans.chomp
             if ansf.casecmp("y") != 0
               @logger.info("Aborted call")
               return
             end
           end
         end

         if !hash_diff[:prods_new].nil? && hash_diff[:prods_new].size > 0
           add_products_from_diffs(hash_diff[:prods_new], zuora_client, wait_for_answer_proc)
         end

         if !hash_diff[:rps_new].nil? && hash_diff[:rps_new].size > 0
           add_rps_from_diffs(hash_diff[:rps_new], zuora_client, wait_for_answer_proc)
         end

         if !hash_diff[:prods_diff_ok].nil? && hash_diff[:prods_diff_ok].size > 0
           modify_prods_from_diffs(hash_diff[:prods_diff_ok], zuora_client, wait_for_answer_proc)
         end

         if !hash_diff[:rps_diff_ok].nil? && hash_diff[:rps_diff_ok].size > 0
           modify_rps_from_diffs(hash_diff[:rps_diff_ok], zuora_client, wait_for_answer_proc)
         end

         if !hash_diff[:prices_update].nil? && hash_diff[:prices_update].size > 0
           update_prices_from_diffs(hash_diff[:prices_update], zuora_client, wait_for_answer_proc)
         end

       rescue ValidationException => exc
         @logger.error(exc.message)
       end
     end

    def sanity_check(hash_diff)
      
      if !hash_diff[:prods_missing].nil? && hash_diff[:prods_missing].size > 0
        missing_products = hash_diff[:prods_missing].collect { |e| e.key } 
        @logger.warn("Missing products #{missing_products.join(",")}")
        raise ValidationException, "Missing products : can't sync with zuora!!"
      end 

      if !hash_diff[:rps_missing].nil? && hash_diff[:rps_missing].size > 0
        missing_rps = hash_diff[:rps_missing].collect { |r| r.key } 
        @logger.warn("Missing rps #{missing_rps.join(",")}")
        raise ValidationException, "Missing RPS: can't sync with zuora!!" 
      end 

      if !hash_diff[:prods_diff_err].nil? && hash_diff[:prods_diff_err].size > 0
        diff_prods = hash_diff[:prods_diff_err].collect { |p| p.key }
        @logger.warn("Modified products #{diff_prods.join(",")}")
        raise ValidationException, "PRODS differ : can't sync with zuora!!" 
      end 

      if !hash_diff[:rps_diff_err].nil? && hash_diff[:rps_diff_err].size > 0
        diff_rps = hash_diff[:rps_diff_err].collect { |r| r.key }
        @logger.warn("Modified rps #{diff_rps.join(",")}")
        raise ValidationException, "RPS differ : can't sync with zuora!!" 
      end 
    end
    
    def add_products_from_diffs(products_diff, zuora_client, wait_for_answer)
      
      products_diff.each do |p|

        # Will retrun from method if confirmation is needed and it is not 'y'
        wait_for_answer.call("Create new product #{p.key}")
        product_private_fields = p.extract_map_from_private_fields
        res = zuora_client.create_product(p.name, p.key, product_private_fields)
        if ! res[0][:success]
          raise ValidationException, "Failed to create product #{p.name}, error #{res[0][:errors][0][:messsage]}"
        end
      end
    end

    def add_rps_from_diffs(prps_diff, zuora_client, wait_for_answer)

      prps_diff.each do |rp|
        # hack ; key should come from product (instead of hardcoding sku)
        z_product = zuora_client.get_product_from_key('sku', rp.product_sku)
        if z_product.size != 1 || z_product[0]['id'].nil?
          raise ValidationException, "Missing product #{rp.product.key} in zuora"
        end

        wait_for_answer.call("Create new rp #{rp.key}")

        # start_date/end_date must be stricly included in the one defined at the product level.
        start_date = z_product[0]['effectiveStartDate'] + 1
        end_date = z_product[0]['effectiveEndDate'] - 1

        rp_private_fields = rp.extract_map_from_private_fields
        res = zuora_client.create_product_rate_plan(rp.name, start_date.to_s, end_date.to_s, z_product[0]['id'], rp_private_fields)
        if ! res[0][:success]
          raise ValidationException, "Failed to create rp #{rp.key}, error #{res[0][:errors][0][:messsage]}"
        end
        
        rp_id = res[0][:id]
        res = zuora_client.create_product_rate_plan_charge(rp.name, rp.accounting_code, rp.billing_period, rp_id, rp.charge_type, rp.prices)
        if ! res[0][:success]
          raise ValidationException, "Failed to create prpc for #{rp.key}, rp.id = #{rp_id},  error #{res[0][:errors][0][:messsage]}"
        end
        @logger.info("Successfully created rp with chargess #{rp.key} : id = #{rp_id}")
      end

    end

    def modify_prods_from_diffs(prods_diff, zuora_client, wait_for_answer)
      
      prods_diff.each do |p|
        
        z_product = zuora_client.get_product_from_sku(p.key, p.key)
        if z_product.size != 1 || z_product[0]['id'].nil?
          raise ValidationException, "Missing product #{rp.product.key} in zuora"
        end
        
        wait_for_answer.call("Update product #{p.key}")
        product_private_fields = p.extract_map_from_private_fields        
        res = zuora_client.update_product(z_product[0]['id'], product_private_fields)
        if ! res[0][:success]
          raise ValidationException, "Failed to update product for #{p.key},  error #{res[0][:errors][0][:messsage]}"
        end
        @logger.info("Successfully updated product #{p.key}")
      end
    end
    
    def modify_rps_from_diffs(rps_diff, zuora_client, wait_for_answer)
      
      rps_diff.each do |rp|
        
        z_prp = zuora_client.get_prp_from_key(rp.key_name, rp.key, rp.private_key?)
        if z_prp.size != 1 || z_prp[0]['id'].nil?
          raise ValidationException, "Missing PRP #{rp.key} in zuora"
        end
        
        wait_for_answer.call("Update prp #{rp.key}")
        rp_private_fields = rp.extract_map_from_private_fields        
        res = zuora_client.update_product_rate_plan(z_prp[0]['id'], rp.name, rp_private_fields)
        if ! res[0][:success]
          raise ValidationException, "Failed to update prp for #{rp.key},  error #{res[0][:errors][0][:messsage]}"
        end
        @logger.info("Successfully updated prp #{rp.key}")

      end
    end
    
    def update_prices_from_diffs(prices_diff, zuora_client, wait_for_answer)
      
      prices_diff.each do |rp|
        
        z_prp = zuora_client.get_prp_from_key(rp.key_name, rp.key, rp.private_key?)
        if z_prp.size != 1 || z_prp[0]['id'].nil?
          raise ValidationException, "Missing PRP #{rp.key} in zuora"
        end
        
        z_prp_id  = z_prp[0]['id']

        z_prpc = zuora_client.get_prpc_from_prp_id_and_much(z_prp_id, rp.billing_period, rp.charge_type)
        if z_prpc.size != 1 || z_prpc[0]['id'].nil?
          raise ValidationException, "Missing PRPC for #{rp.key} #{rp.billing_period}  #{rp.charge_type} in zuora"
        end
        
        z_prpc_id = z_prpc[0]['id']
        
        z_prpct = zuora_client.get_prpct_from_prpc_id(z_prpc_id)
        z_prpct.each do | cur |
          
          
          cur_id = cur['id']
          cur_price = cur['price']
          cur_currency = cur['currency']                    


          rp_price_for_currency = rp.price_for_currency(cur_currency)
          if rp_price_for_currency != cur_price
            
            wait_for_answer.call("Updating #{rp.key} currency #{cur_currency} from #{cur_price} -> #{rp_price_for_currency}")
            
            res = zuora_client.update_one_currency(cur_id, rp_price_for_currency)
            if ! res[0][:success]
              raise ValidationException, "Failed to update price for #{rp.key} currency #{cur_currency}"
            end
          end
        end
        
      end
       
    end

    def cross_validation_from_csvs(ref_csv, check_csv)
      
      # Compare zuora catalog to master CSV version
      prods_miss = [] # missing produtcs from base CSV => error
      prods_diff_err = [] # diff produtcs from base CSV => error
      prods_diff_ok = [] # diff produtcs from base CSV => OK (private fields)    
      rps_miss = [] # missing rps from base CSV => error
      rps_diff_err = [] # diff rps from base CSV => error
      rps_diff_ok = [] # diff rps from base CSV => OK (private fields)      
      price_updates = [] # updates in rps => OK

      @logger.info("1. Comparing zuora catalog to csv...")

      compare_csv_catalogs(ref_csv, check_csv, prods_miss, prods_diff_err, prods_diff_ok, rps_miss, rps_diff_err, rps_diff_ok, price_updates)
      if prods_miss.size != 0
        prods_miss_sku = prods_miss.collect { |p| p.key } 
        @logger.info("\tMISSING PRODUCTS : NOK #{prods_miss.size.to_s} (#{prods_miss_sku.join(",")})")
      else
        @logger.info("\tMISSING PRODUCTS : OK")
      end

      if prods_diff_err.size != 0
        prods_diff_err_sku = prods_diff_err.collect { |p| p.key}
        @logger.info("\tPRODUCT INCONSISTENCIES : NOK #{prods_diff_err.size.to_s} (#{prods_diff_err_sku.join(",")})")
      else
        @logger.info("\tPRODUCT INCONSISTENCIES : OK")
      end

      if rps_miss.size != 0
        rps_miss_key = rps_miss.collect { |rp| rp.key }
        @logger.info("\tMISSING RATE PLANS : NOK #{rps_miss.size.to_s} (#{rps_miss_key.join(",")})")
      else
        @logger.info("\tMISSING RATE PLANS : OK")
      end

      if rps_diff_err.size != 0
        rps_diff_err_key = rps_diff_err.collect { |rp| rp.key}
        @logger.info("\tRP INCONSISTENCIES : NOK #{rps_diff_err.size.to_s} (#{rps_diff_err_key.join(",")})")
      else
        @logger.info("\tRP INCONSISTENCIES : OK")
      end

      if price_updates.size > 0
        price_updates_key = price_updates.collect { |rp| rp.key }
        @logger.info("\tPRICES DIFFER FROM BASE CSV : NOK #{price_updates.size.to_s} (#{price_updates_key.join(",")})")
      else
        @logger.info("\tPRICES DIFFERERENCE FROM BASE CSV : OK")        
      end
      
      if prods_diff_ok.size != 0
        prods_diff_ok_sku = prods_diff_ok.collect { |p| p.key }
        @logger.info("\tPRODUCT DIFFERENCES : NOK #{prods_diff_ok.size.to_s} (#{prods_diff_ok_sku.join(",")})")        
      else
        @logger.info("\tPRODUCT DIFFERENCES : OK")                
      end

      if rps_diff_ok.size != 0
        rps_diff_ok_key = rps_diff_ok.collect { |rp| rp.key }
        @logger.info("\tRP DIFFERENCES : NOK #{rps_diff_ok.size.to_s} (#{rps_diff_ok_key.join(",")})")        
      else
        @logger.info("\tRP DIFFERENCES : OK")                
      end
    
      # Compare master CSV to zuora catalog
      prods_new = []
      prods_diff_err_again = []
      rps_diff_err_again = []      
      rps_new = []
      price_updates_again = []

      @logger.info("2. Comparing csv to zuora catalog")
      compare_csv_catalogs(check_csv, ref_csv, prods_new, prods_diff_err_again, nil, rps_new, rps_diff_err_again, nil, price_updates_again)
      if prods_diff_err_again.size != prods_diff_err.size || rps_diff_err_again.size != rps_diff_err.size
        @logger.warn("Got prods diff : #{prods_diff_err_again.size} != #{prods_diff_err.size} and rp diffs #{rps_diff_err_again.size} -> #{rps_diff_err.size}")
        raise ValidationException, "Internal error: we should get same answer about difference when checking new <-> ref"
      end

      if price_updates_again.size != price_updates.size
        raise ValidationException, "Internal error: updates in rate plans should get same answer when checking new <-> ref"
      end
      
      if prods_new.size != 0
        prods_new_sku = prods_new.collect { |p| p.key }
        @logger.info("\tNEW PRODUCTS : NOK #{prods_new.size} (#{prods_new_sku.join(",")})")
      else
        @logger.info("\tNEW PRODUCTS : OK")        
      end

      if rps_new.size != 0
        rps_new_key = rps_new.collect { |rp| rp.key }
        @logger.info("\tNEW RPS : NOK #{rps_new.size} (#{rps_new_key.join(",")})")
      else
        @logger.info("\tNEW RPS : OK")
      end

      # Returns all differences found
      { :prods_missing => prods_miss,
        :rps_missing => rps_miss,
        :prods_diff_err => prods_diff_err,          
        :rps_diff_err => rps_diff_err,          
        :prods_new => prods_new,
        :rps_new => rps_new,
        :prods_diff_ok => prods_diff_ok,          
        :rps_diff_ok => rps_diff_ok,          
        :prices_update => price_updates
      }               
    end

    
    def compare_csv_catalogs(csv1, csv2, prods_miss, prods_diff_err, prods_diff_ok, rps_miss, rps_diff_err, rps_diff_ok, price_updates)

      res = true
      csv1.csv_products.each do |p1|
        found = false
        csv2.csv_products.each do |p2|

          if p1.key == p2.key
            is_same = p1.is_same(p2, prods_diff_err, prods_diff_ok, rps_miss, rps_diff_err, rps_diff_ok, price_updates)
            res = false unless is_same
            found = true
          end
        end
        if !found
          prods_miss.push(p1)
          res = false
        end
      end
      res
    end
  end
end

