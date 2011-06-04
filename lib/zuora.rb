$:.unshift File.join(File.dirname(__FILE__),'.')

require 'rubygems'
require 'logger'
require 'zuora_client'
require 'json'

require "config"

module CatalogTool
  module Zuora

    PRODUCT_START_DATE = "2006-01-01T00:00:00.000Z"
    PRODUCT_END_DATE = "2060-01-01T00:00:00.000Z"

    def self.private_fields
      ZuoraClient.parse_custom_fields
    end
    
    class API
      attr_accessor :url, :user, :pwd, :client, :product_custom_fields, :prp_custom_fields


      def initialize(config)
        @url = config.zuora_url
        @user = config.zuora_user
        @pwd = config.zuora_pwd
        @client = ZuoraClient.new(user, pwd, url)
        custom_fields = ZuoraClient.parse_custom_fields
        extract_private_fields(custom_fields)

      end
      
      #
      # Catalog modification
      #
      def create_product(name, sku, private_fields)   
        
        p private_fields     
        product = ZUORA::Product.new
        product.effectiveStartDate = Zuora::PRODUCT_START_DATE
        product.effectiveEndDate = Zuora::PRODUCT_END_DATE
        product.name = name unless name.nil?
        product.sKU = sku
        set_private_fields(product, private_fields)

        result = client.create([product])
      end


      def create_product_rate_plan(name, startDate, endDate, product_id, private_fields)
        prp = ZUORA::ProductRatePlan.new
        prp.effectiveStartDate = (startDate == nil) ?  Zuora::PRODUCT_START_DATE : startDate
        prp.effectiveEndDate = (endDate == nil) ? Zuora::PRODUCT_END_DATE : endDate
        prp.name = name unless name.nil?
        prp.productId = product_id
        set_private_fields(prp, private_fields)        

        result = client.create([prp])
      end

      def create_product_rate_plan_charge(name, code, billing_period, prp_id, charge_type, prices)

        rev_code = (billing_period == "Month") ? "Monthly" : billing_period

        prpc = ZUORA::ProductRatePlanCharge.new
        prpc.name = name unless name.nil?
        prpc.accountingCode = code
        prpc.revRecCode = rev_code #rev_code # Monthly/Annual
        prpc.chargeModel = "FlatFee" # Tiered, PerUnit ...
        prpc.triggerEvent = "ContractEffective"
        prpc.billingPeriod = billing_period # Month Annual ...
        prpc.billCycleType = (billing_period == "Month") ? "DefaultFromCustomer" : "SubscriptionStartDay"
        prpc.billingPeriodAlignement = "AlignToCharge"
        prpc.revRecTriggerCondition = "ContractEffectiveDate"
        prpc.productRatePlanId = prp_id
        prpc.chargeType = charge_type # OneTime, Recurring, Usage
        tierData = ZUORA::ProductRatePlanChargeTierData.new
        chargeTier = []

        if prices.size != Currency.size
          return false
        end

        Currency.each_with_index do |c, i|
          chargeTier[i] = ZUORA::ProductRatePlanChargeTier.new
          chargeTier[i].active = true
          chargeTier[i].currency = c.value
          chargeTier[i].price = prices[i]
        end
        tierData.productRatePlanChargeTier = chargeTier
        prpc.productRatePlanChargeTierData = tierData
        result = client.create([prpc])
      end

      def update_product(id, private_fields)
        product = ZUORA::Product.new
        product.id = id
        set_private_fields(product, private_fields)

        result = client.update([product])
      end

      def update_product_rate_plan(id, name, private_fields)
        prp = ZUORA::ProductRatePlan.new
        prp.id = id
        prp.name = name unless name.nil?
        set_private_fields(prp, private_fields)

        result = client.update([prp])
      end

      def update_product_rate_plan_charge(prpc_id, name, code, billing_period)

        rev_code = (billing_period == "Month") ? "Monthly" : billing_period

        prpc = ZUORA::ProductRatePlanCharge.new
        prpc.id = prpc_id
        prpc.name = name unless name.nil?
        prpc.accountingCode = code unless code.nil?
        prpc.revRecCode = rev_code unless billing_period.nil? #rev_code # Monthly/Annual
        prpc.billingPeriod = billing_period # Month Annual ...
        result = client.update([prpc])
      end


      def delete_product(p_id)
        result = client.delete('Product',  [p_id])
      end

      def delete_product_rate_plan(prp_id)
        result = client.delete('ProductRatePlan',  [prp_id])
      end
      
      def delete_product_rate_plan_charge(prpc_id)
        result = client.delete('ProductRatePlanCharge',  [prpc_id])
      end


      def update_one_currency(prpct_id, new_price)

        prpct = ZUORA::ProductRatePlanChargeTier.new
        prpct.id = prpct_id
        prpct.price = new_price

        result = client.update([prpct])
      end

      #
      # Catalog Retrieval
      #
      def get_product_from_key(key, key_value, private_key=false)
        key = format_key(key) if private_key
        fields = get_query_fields("Id, Description, EffectiveEndDate, EffectiveStartDate, Name, SKU", @product_custom_fields)
        @client.query("select #{fields} from Product where #{key} = '#{key_value}'")
      end

      def get_prp_from_key(key, key_value, private_key=false)
        key = format_key(key) if private_key
        fields = get_query_fields("Id, Description, EffectiveEndDate, EffectiveStartDate, Name, ProductId", @prp_custom_fields)        
        @client.query("select #{fields} from ProductRatePlan where #{key} = '#{key_value}'")
      end

      def get_all_products()
        fields = get_query_fields("Id, Description, EffectiveEndDate, EffectiveStartDate, Name, SKU", @product_custom_fields)        
        @client.query("select #{fields} from Product")
      end

      def get_prp_for_prod_id(prod_id)
        fields = get_query_fields("Id, Description, EffectiveEndDate, EffectiveStartDate, Name, ProductId", @prp_custom_fields)  
        @client.query("select #{fields} from ProductRatePlan where ProductId = '#{prod_id}'")
      end

      def get_prpc_from_prp_id(prp_id)
        fields = get_query_fields("Id, AccountingCode, DefaultQuantity, MaxQuantity, MinQuantity, Name, ProductRatePlanId,  BillingPeriod, ChargeType", nil)                        
        @client.query("select #{fields} from ProductRatePlanCharge where ProductRatePlanId = '#{prp_id}'")
      end

      def get_prpc_from_prp_id_and_much(prp_id, billing_period, charge_type)
        fields = get_query_fields("Id, AccountingCode, DefaultQuantity, MaxQuantity, MinQuantity, Name, ProductRatePlanId, BillingPeriod, ChargeType", nil)                        
        @client.query("select #{fields} from ProductRatePlanCharge where ProductRatePlanId = '#{prp_id}' and BillingPeriod = '#{billing_period}' and ChargeType = '#{charge_type}'")
      end

      def get_prpct_from_prpc_id(prpc_id)
        fields = get_query_fields("Id, ProductRatePlanChargeId, Price, Currency, Tier", nil)                        
        @client.query("select #{fields} from ProductRatePlanChargeTier where ProductRatePlanChargeId = '#{prpc_id}'")
      end
      
      # Expect string CamelCase => return string with first letter lowercase and postfixed by "__c"
      def self.format_private_field(input)
        result = input.gsub(/^\w/) { |i| i.downcase }
        result = "#{result}__c"
      end
      
      
      private
      
      def extract_private_fields(private_fields)

        @product_custom_fields = []
        @prp_custom_fields = []

        private_fields.each do |key, value|
          fields = value.strip.split(/\s+/).map { |e| "#{e}" }
          if key == "Product"
            @product_custom_fields = fields
          elsif key == "ProductRatePlan"
            @prp_custom_fields = fields
          end
        end
      end


      def set_private_fields(obj, private_fields)
        if private_fields
          private_fields.each do |k,v|
            if v
              k = API.format_private_field(k)
              setter = "#{k}=".to_sym
              obj.send(setter, v)
            end
          end
        end
      end
      
      def format_key(key)
        result = "#{key}__c"
      end
      
      # Inject private fields as needed
      def get_query_fields(initial_fields, private_fields)
        fields = initial_fields
        if private_fields
          private_fields.each do |f|
            fields = fields + ", #{f}__c" 
          end
        end
        fields
      end
    end

  end
end

