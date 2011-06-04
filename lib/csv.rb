$:.unshift File.join(File.dirname(__FILE__),'.')

require 'rubygems'
require 'logger'
require 'zuora_client'
require 'json'
require 'yaml'

require "util"
require "currency"
require "catalog"

module CatalogTool

  class CSVCatalogException < Exception

  end


  class CSVObject
    include StringUtils

    # Should we overwrite default keys 
    KEY_YML = File.dirname(File.expand_path(__FILE__)) + "/../conf/csv_key.yml"
    
    attr_reader :validation_map,  :key_default_field, :key_field, :private_list 

    def initialize(class_name, validation_map, key_field, private_list)

      @private_list = []
      @key_default_field = key_field
      @key_field = key_field      
      @validation_map = validation_map
      
      # Check if we want to overwrite the default keys for the CSV objects
      read_key_field(class_name)
      
      # Inject private fields and set value
      if private_list
        type_class = Object.const_get('CatalogTool').const_get(class_name)
        private_list.each do |k,v|
          @private_list << k
          field = camel_to_underscore(k)
          type_class.send :attr_accessor, field.to_sym
          setter = "#{field}=".to_sym
          self.send(setter, v)
        end    
      end  
    end

    def extract_map_from_private_fields
      result = {}
      @private_list.each do |f_camel|
        f = camel_to_underscore(f_camel)
        getter = "#{f}".to_sym
        value = self.send(getter)
        result[f_camel] = value
      end
      result
    end

    def validate_fields
      methods.each do |m|
        callback = @validation_map[m] unless @validation_map.nil?
        if callback
          getter = "#{m}".to_sym
          value = self.send(getter)        
          callback.call(m, @key_field, value)
        end
      end
    end

    def key_name
      @key_field.sub(/^\w/) { |i| i.upcase }
    end
    
    def key
      getter = "#{key_field}".to_sym
      self.send(getter)
    end
    
    def private_key?
      @key_field != @key_default_field
    end
    
    private
    
    def read_key_field(class_name)
      if File.exist?(KEY_YML)
        keys = YAML.load_file(KEY_YML)
        if keys[class_name.to_s]
          if defined?(keys[class_name.to_s]['key'])
            @key_field = keys[class_name.to_s]['key']
          end
        end
      end
    end

  end


  class CSVProduct < CSVObject

    DEFAULT_KEY_FIELD_PRODUCT = 'sku'

    attr_reader :logger
    attr_accessor :sku, :name, :rps

    def initialize(logger, validation_map, sku, name, private_fields)
      @sku = sku
      @name = name
      @logger = logger
      @rps = []
      super('CSVProduct', validation_map, DEFAULT_KEY_FIELD_PRODUCT, private_fields)

      validate_fields
    end


    def is_same(csv_prod, prods_diff, prods_diff_ok, rp_miss, rp_diffs, rp_diffs_ok, price_updates)

      res = true
      if ! is_same_string?(@name, csv_prod.name)
        @logger.debug("product #{sku} differs #{@name} -> #{csv_prod.name}")
        prods_diff.push(csv_prod)
        res = false
      end

      @private_list.each do |priv|

        priv = camel_to_underscore(priv)
        getter = "#{priv}".to_sym
        if !is_same_string?(self.send(getter), csv_prod.send(getter))
          @logger.debug("product #{sku} differs for field #{priv} : #{self.send(getter)} ->  #{csv_prod.send(getter)}")
          prods_diff_ok.push(csv_prod) unless prods_diff_ok.nil? || prods_diff_ok.include?(csv_prod)
        end
      end

      rps.each_with_index do |rp1, i|

        found = false
        csv_prod.rps.each do |rp2|
          if is_same_string?(rp1.key, rp2.key) &&
            is_same_string?(rp1.charge_type, rp2.charge_type)
            found = true
            is_same = rp1.is_same(rp2, rp_diffs_ok, price_updates)
            if !is_same
              rp_diffs.push(rp1)
              res = false
              @logger.debug("prod #{@sku} does not have same rp #{rp1.key} as peer")
            end
          end
        end
        if !found
          rp_miss.push(rp1)
          res = false
          @logger.debug("prod #{@sku} peer does not have rp #{rp1.key}")
        end
      end
      res
    end
  end

  class CSVRP  < CSVObject

    DEFAULT_KEY_FIELD_RP = 'name'

    attr_reader :logger
    attr_accessor :product_sku, :name, :billing_period, :accounting_code, :charge_type
    attr_accessor *(Currency.collect { |c| c.value.downcase.to_sym  })

    def initialize(logger, validation_map, product_sku, name, billing_period, accounting_code, charge_type, private_fields, *currencies)

      @product_sku = product_sku
      @name = name
      @billing_period = billing_period
      @accounting_code = accounting_code
      @charge_type = charge_type

      @logger = logger

      super('CSVRP', validation_map, DEFAULT_KEY_FIELD_RP, private_fields)

      if !currencies.nil? && currencies.size > 0
        Currency.each_with_index do |c, i|
          cur_currency = c.value.downcase
          setter = "#{cur_currency}=".to_sym
          self.send(setter, currencies[i])
        end
      end

      validate_fields
    end

    def prices
      prices = []
      Currency.each do |c|
        prices.push(send(c.value.downcase.to_sym))
      end
      prices
    end

    def price_for_currency(currency)
      send(currency.downcase.to_sym)
    end

    def is_same(csv_rp, rp_diffs_ok, price_updates)


      if ! is_same_string?(@billing_period,csv_rp.billing_period)
        @logger.debug("billing_period #{@billing_period} is different than #{csv_rp.billing_period}")
        return false
      end
      if ! is_same_string?(@accounting_code,csv_rp.accounting_code)
        @logger.debug("accounting_code #{@accounting_code} is different than #{csv_rp.accounting_code}")
        return false
      end
      if ! is_same_string?(@charge_type,csv_rp.charge_type)
        @logger.debug("charge_type #{@charge_type} is different than #{csv_rp.charge_type}")
        return false
      end

      @private_list.each do |priv|

        priv = camel_to_underscore(priv)
        getter = "#{priv}".to_sym

        # Check private fields
        if !is_same_string?(self.send(getter), csv_rp.send(getter))
          @logger.debug("#{priv} #{self.send(getter)} is different than #{csv_rp.send(getter)}")
          rp_diffs_ok.push(csv_rp) unless rp_diffs_ok.nil? || rp_diffs_ok.include?(csv_rp)
        end
      end




      price_differs = false
      Currency.each_with_index do |c, i|
        cur_currency = c.value.downcase
        getter = "#{cur_currency}".to_sym
        if (self.send(getter) != csv_rp.send(getter))
          @logger.debug("price differs for rp = #{self.key} for currency #{c.value}: #{self.send(getter)} => #{csv_rp.send(getter)} ")
          price_updates.push(csv_rp) unless price_differs
          price_differs = true
          break
        end
      end
      true
    end
  end


  class CSVCatalog

    attr_reader :logger, :product_private_fields, :rp_private_fields, :lambda_extract_prices
    attr_accessor :csv_string, :csv_products

    def initialize(logger, private_fields)

      @logger = logger
      extract_private_fields(private_fields )
      @csv_string = ""
      @csv_products = []

      # Extract ordered list of prices from incoming zuora catalog
      @lambda_extract_prices = lambda { |prices, prpc|
        Currency.each_with_index do |c, i|
          found = false
          prpc.children.each do |prpct|
            if prpct.hash['currency'] == c.value
              prices[i] = prpct.hash['price']
              found = true
            end
          end
          if !found
            prices[i] = -1
          end
        end
      }
    end

    def extract_private_fields(private_fields)

      @product_private_fields = []
      @rp_private_fields = []

      private_fields.each do |key, value|
        fields = value.strip.split(/\s+/).map { |e| "#{e}" }
        if key == "Product"
          @product_private_fields = fields
        elsif key == "ProductRatePlan" || key == "ProductRatePlanCharge" || key == "ProductRatePlanTier"
          @rp_private_fields.concat(fields)
        end
      end
    end

    # Replace ^M as a separator with ;
    CSV_CONTROL_M_BYTE = 13
    CSV_SEMI_COLUMN_BYTE = 59

    CSV_NEWCR = ";"
    CSV_SEP = ","

    CSV_PROD_CATALOG_START = "Product Catalog"
    CSV_RP_CATALOG_START = "Rate Plans"

    CSV_PROD_HEADER_LENGTH = 2 # does not include private fields
    CSV_PROD_HEADER_SKU = "SKU"
    CSV_PROD_HEADER_NAME = "Name"

    CSV_RP_HEADER_LENGTH = 5 # does not include private fields and currencies 
    CSV_RP_HEADER_PSKU = "ProductSKU"
    CSV_RP_HEADER_NAME = "Name"
    CSV_RP_HEADER_BILLING_PERIOD = "BillingPeriod"
    CSV_RP_HEADER_ACCN = "AccountingCode"
    CSV_RP_HEADER_CHT = "ChargeType"


    def extract_private_from_hash(the_hash)
      result = {}
      re = /(\w+)__c/
      the_hash.each do |k, v|
        if re.match(k)
          result[$1] = v
        end
      end
      result
    end


    def extract_from_z_catalog(catalog)

      @logger.debug("extract_from_z_catalog START")

      catalog.products.each do |p|

        product_private_hash = extract_private_from_hash(p.hash)
        csv_prod = CSVProduct.new(@logger, nil, p.hash['sKU'], p.hash['name'], product_private_hash)

        prices = []
        p.children.each do |prp|

          name = prp.hash['name']
          rp_private_hash = extract_private_from_hash(prp.hash)

          if prp.children.nil? || prp.children.size == 0
            csv_rp = CSVRP.new(@logger, nil, p.hash['sKU'], name, nil, nil, nil, rp_private_hash, nil)
            csv_prod.rps.push(csv_rp)
          else
            prp.children.each do |prpc|
              accounting_code = prpc.hash['accountingCode']
              charge_type = prpc.hash['chargeType']
              billing_period = prpc.hash['billingPeriod']
              @lambda_extract_prices.call(prices, prpc)

              csv_rp = CSVRP.new(@logger, nil, p.hash['sKU'], name, billing_period, accounting_code, charge_type, rp_private_hash, *prices)
              csv_prod.rps.push(csv_rp)

            end
          end
        end
        @logger.debug("adding product #{csv_prod.sku}")
        @csv_products.push(csv_prod)
      end

      @logger.debug("extract_from_z_catalog DONE")
    end


    def get_first_header_prod
      CSV_PROD_HEADER_SKU + ","
    end

    def get_first_header_rp
      CSV_RP_HEADER_PSKU + ","
    end

    def get_length_header_prod
      CSV_PROD_HEADER_LENGTH + @product_private_fields.size
    end

    def get_length_header_rp
      CSV_RP_HEADER_LENGTH + @rp_private_fields.size + Currency.size
    end


    def validate_header_prod(input)



      if input.size != get_length_header_prod
        raise CSVCatalogException, "Invalid number of product headers #{input.size} -> #{get_length_header_prod}"
      end

      new_product_private_fields = []
      input.each_with_index do |h, i|
        case i
        when 0
          if h != CSV_PROD_HEADER_SKU
            raise CSVCatalogException, "Invalid field #{i} for product header : #{h} != #{CSV_PROD_HEADER_SKU} "
          end
        when 1
          if h != CSV_PROD_HEADER_NAME
            raise CSVCatalogException, "Invalid field #{i} for product header : #{h} != #{CSV_PROD_HEADER_NAME}"
          end
        else
          found = false
          @product_private_fields.each do |f|
            if f == h
              found = true
              new_product_private_fields << h
              break
            end
          end
          if !found
            raise CSVCatalogException, "Could not find Product private field #{h}"
          end
        end
      end
      # Reorder fields...
      @product_private_fields = new_product_private_fields
    end


    def validate_header_rp(input)

      if input.size != get_length_header_rp
        raise CSVCatalogException, "Invalid number of rate plans headers"
      end


      new_rp_private_fields = []

      input.each_with_index do |h, i|
        case i
        when 0
          if h != CSV_RP_HEADER_PSKU
            raise CSVCatalogException, "Invalid field #{i} for rp header"
          end
        when 1
          if h != CSV_RP_HEADER_NAME
            raise CSVCatalogException, "Invalid field #{i} for rp header"
          end
        when 2
          if h != CSV_RP_HEADER_BILLING_PERIOD
            raise CSVCatalogException, "Invalid field #{i} for rp header"
          end
        when 3
          if h != CSV_RP_HEADER_ACCN
            raise CSVCatalogException, "Invalid field #{i} for rp header"
          end
        when 4
          if h != CSV_RP_HEADER_CHT
            raise CSVCatalogException, "Invalid field #{i} for rp header"
          end
        else
          if i < CSV_RP_HEADER_LENGTH + @rp_private_fields.size
            found = false
            @rp_private_fields.each do |f|
              if f == h
                found = true
                new_rp_private_fields << h
                break
              end
            end
            if !found
              raise CSVCatalogException, "Could not find RP private field #{h}"
            end
          else
            found = false
            Currency.each do |c|
              if CSV_RP_HEADER_LENGTH + + @rp_private_fields.size + c.label == i
                if h != c.value
                  raise CSVCatalogException, "Invalid field #{i} for currency rp header #{h}"
                end
                found = true
              end
            end
            if !found
              raise CSVCatalogException, "Invalid currency #{h} at position #{i}"
            end
          end
        end
      end
      # Reorder fields
      @rp_private_fields =  new_rp_private_fields 
    end
  end


  class CSVCatalogReader < CSVCatalog
    
    class CSVStateMachine
      extend Enum
      self.add_enum(:INIT, 0)
      self.add_enum(:FOUND_PROD_CATALOG, 1)
      self.add_enum(:FOUND_PROD_HEADERS, 2)
      self.add_enum(:FOUND_RP_CATALOG, 3)
      self.add_enum(:FOUND_RP_HEADERS, 4)
      self.add_enum(:DONE, 5)
    end

    attr_reader :input_file, :sanity_product_callbacks, :sanity_rp_callbacks
    attr_accessor  :products, :rate_plans


    def initialize(logger, validation_config, private_fields, input_file)
      super(logger, private_fields)

      @input_file = input_file
      @sanity_rp_callbacks = nil
      @sanity_product_callbacks = nil

      eval_from_sanity_validation_config(validation_config)

      read_from_file
    end


    private
    
    #
    # If there is sanity validation file config, eval the file to extract
    # the validation callbacks
    #
    def eval_from_sanity_validation_config(validation_config)

      begin
        if validation_config && File.exist?(validation_config)
          eval_sanity = ""
          File.open(validation_config, 'r') do |f|
            while line = f.gets
              eval_sanity += line
            end
          end
          # Eval callback files
          eval eval_sanity
          if defined?(CatalogTool::Sanity::SANITY_PRODUCT)
            @sanity_product_callbacks = CatalogTool::Sanity::SANITY_PRODUCT
          end
          if defined?(CatalogTool::Sanity::SANITY_RP)
            @sanity_rp_callbacks = CatalogTool::Sanity::SANITY_RP
          end
        end
      rescue SyntaxError => err
        log.warn("Failed eval sanity validation strings from file #{validation_config}")
      end
      
    end

    def read_from_file

      line = nil
      begin

        bytes = []

        File.open(@input_file, 'r') do |fin|

          index = 0
          fin.each_byte do |b|
            index += 1
            if b == CSV_CONTROL_M_BYTE
              b = CSV_SEMI_COLUMN_BYTE
            end
            bytes.push(b)
          end

          line = bytes.map {|num| num.chr}.join
          # Excel changes case for boolean value...
          line.gsub!(/TRUE/, 'true')
          line.gsub!(/FALSE/, 'false')          
          @logger.debug("Got CSV line #{line}")
        end
      rescue Exception => err
        @logger.error("Failed to parse file #{@input_file} : #{err.message}")
      end
      if ! line.nil?

        @csv_string = line

        products_hash = Hash.new

        parse_csv do |state, e|
          @logger.debug("\t ****************  Got entry #{e} for state = #{state.value.to_s()} (#{state.label.to_s()})} ")
          if state == CSVStateMachine::FOUND_PROD_HEADERS

            sku, name, *read_private_fields = e.split(CSV_SEP)            
            hash_product_private = {}
            @product_private_fields.each_with_index do |f, i|
              hash_product_private[f] = read_private_fields[i]
            end
            csv_product = CSVProduct.new(@logger, @sanity_product_callbacks, sku, name, hash_product_private)
            products_hash[sku] = csv_product
          elsif state == CSVStateMachine::FOUND_RP_HEADERS
            # read_remaining contains both private fields and currencies
            product_sku, name, billing_period, accounting_code, charge_type, *read_remaining = e.split(CSV_SEP)
            hash_rp_private = {}
            @rp_private_fields.each_with_index do |f, i|
              hash_rp_private[f] = read_remaining.shift 
            end
            prices = read_remaining

            csv_product = products_hash[product_sku]
            if csv_product.nil?
              raise CSVCatalogException, "Error in state machine, no active product #{product_sku} for #{e}"
            end
            csv_rp = CSVRP.new(@logger, @sanity_rp_callbacks, product_sku, name, billing_period, accounting_code, charge_type, hash_rp_private, *(prices.collect! {|p| Float(p)}))
            csv_product.rps.push(csv_rp)
          end
        end

        products_hash.each_key do |k|
          csv_prod = products_hash[k]
          @csv_products.push(csv_prod)
        end
      end
    end

    def parse_csv

      @logger.debug("Starting parse_csv #{@csv_string}")
      state =  CSVStateMachine::INIT

      reading_prod_catalog = false
      reading_prod_catalog = false
      entries = @csv_string.split(CSV_NEWCR)

      entries.each_with_index do |e, i|

        if e.nil? || e == ""
          next
        end

        @logger.debug("-> Got entry #{e}")

        if e.start_with?(CSV_PROD_CATALOG_START)
          state = CSVStateMachine::FOUND_PROD_CATALOG
          @logger.debug("Got Product title  #{e}")
        elsif e.start_with?(get_first_header_prod)
          @logger.debug("Got Product header  #{e}")
          parts = e.split(",")
          validate_header_prod(parts)
          state = CSVStateMachine::FOUND_PROD_HEADERS
        elsif e.start_with?(CSV_RP_CATALOG_START)
          @logger.debug("Got RP title  #{e}")
          state =  CSVStateMachine::FOUND_RP_CATALOG
        elsif e.start_with?(get_first_header_rp)
          @logger.debug("Got RP header  #{e}")
          state = CSVStateMachine::FOUND_RP_HEADERS
          parts = e.split(",")
          validate_header_rp(parts)
        elsif e.nil?
        else
          if state == CSVStateMachine::FOUND_PROD_HEADERS
            yield(state, e)
          elsif state == CSVStateMachine::FOUND_RP_HEADERS
            yield(state, e)
          else
          end
        end
        @logger.debug("-> Done with entry #{e} state = #{state.value.to_s()} (#{state.label.to_s()})\n\n")
      end
      @logger.debug("DONE parse_csv")
    end
  end


  class CSVCatalogWriter < CSVCatalog

    include StringUtils

    attr_reader :catalog

    def initialize(logger, private_fields, catalog)
      super(logger, private_fields)
      @catalog = catalog
    end

    def export_to_file(file_name)
      #begin
      extract_from_z_catalog(@catalog)
      create_product_header
      add_products
      create_rp_header
      add_rps
      patch_csv_string
      File.open(file_name, "w") do |out|
        out.write(@csv_string)
      end
      #rescue Exception => err
      #  @logger.error("Failed to export to file #{file_name} : #{err.message}")
      #end
    end

    private

    def patch_csv_string
      index = 0
      copy = @csv_string
      bytes = []
      copy.each_byte do |b|
        index += 1
        if b == CSV_SEMI_COLUMN_BYTE
          b = CSV_CONTROL_M_BYTE
        end
        bytes.push(b)
      end
      @csv_string = bytes.map {|num| num.chr}.join
    end

    def add_csv_sep(count)
      count.times do |c|
        @csv_string += CSV_SEP
      end
    end

    def add_csv_cr(count)
      count.times do |c|
        @csv_string += CSV_NEWCR
      end
    end

    def create_product_header

      @logger.debug("create_product_header START")
      @csv_string += CSV_PROD_CATALOG_START
      add_csv_sep(get_length_header_prod - 1)
      add_csv_cr(2)
      @csv_string += CSV_PROD_HEADER_SKU
      add_csv_sep(1)
      @csv_string += CSV_PROD_HEADER_NAME

      @product_private_fields.each do |f|
        add_csv_sep(1)
        @csv_string += f
      end
      add_csv_cr(1)
    end

    def create_rp_header

      @logger.debug("create_rp_header START")
      add_csv_cr(2)
      @csv_string += CSV_RP_CATALOG_START
      add_csv_sep(get_length_header_rp - 1)
      add_csv_cr(2)
      @csv_string += CSV_RP_HEADER_PSKU
      add_csv_sep(1)
      @csv_string += CSV_RP_HEADER_NAME
      add_csv_sep(1)
      @csv_string += CSV_RP_HEADER_BILLING_PERIOD
      add_csv_sep(1)
      @csv_string += CSV_RP_HEADER_ACCN
      add_csv_sep(1)
      @csv_string += CSV_RP_HEADER_CHT
      @rp_private_fields.each do |f|
        add_csv_sep(1)        
        @csv_string += f
      end

      Currency.each_with_index do |c, i|
        add_csv_sep(1)
        @csv_string += c.value
      end
      add_csv_cr(1)
    end

    def add_products

      @logger.debug("add_products START")

      @csv_products.each do |p|
        @csv_string += p.sku
        add_csv_sep(1)
        @csv_string += p.name

        @product_private_fields.each do |f|
          add_csv_sep(1)
          f = camel_to_underscore(f)
          getter = "#{f}".to_sym
          value= p.send(getter)
          @csv_string += value unless value.nil?
        end
        add_csv_cr(1)
      end
    end

    def add_rps

      @logger.debug("add_rps START")

      @csv_products.each do |p|
        p.rps.each do |rp|
          @csv_string += p.sku
          add_csv_sep(1)
          @csv_string += rp.name unless !rp.name
          add_csv_sep(1)
          @csv_string += rp.billing_period unless !rp.billing_period
          add_csv_sep(1)
          @csv_string += rp.accounting_code unless !rp.accounting_code
          add_csv_sep(1)
          @csv_string += rp.charge_type unless !rp.charge_type

          @rp_private_fields.each do |f|
            add_csv_sep(1)            
            f = camel_to_underscore(f)
            getter = "#{f}".to_sym
            value = rp.send(getter)
            @csv_string += value unless value.nil?            
          end

          rp.prices.each do |price|
            add_csv_sep(1)
            @csv_string += price.to_s
          end
          add_csv_cr(1)
        end
      end

      @logger.debug("add_rps STOP")
    end
  end
end

