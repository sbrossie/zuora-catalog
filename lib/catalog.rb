$:.unshift File.join(File.dirname(__FILE__),'.')

require 'rubygems'
require 'logger'
require 'zuora_client'


module CatalogTool


#
# Catalog representation obtained from fetching from zuora or loading from dump file
#
  class ZuoraCatalog

    attr_accessor :products, :zuora_api, :logger

    def initialize(zuora_api, logger)
      @zuora_api = zuora_api
      @logger = logger
      @products = []
    end

    def z_fetch(product_filter=nil)

      @zuora_api.get_all_products.each() do |prod| 

        if product_filter.nil? || product_filter == prod['sKU']

          @logger.debug("PROD (FILTER) = #{prod.inspect}, class = #{prod.class}")

          prps = @zuora_api.get_prp_for_prod_id(prod['id'])
          x_prps = []
          prps.each() do |prp|

            @logger.debug("\tPRP = #{prp.inspect}, class = #{prp.class}")
            

            prpcs = @zuora_api.get_prpc_from_prp_id(prp['id'])
            x_prpcs = []
            prpcs.each() do |prpc|

              @logger.debug("\t\tPRPC = #{prpc.inspect}, class = #{prpc.class}")

              prpcts = @zuora_api.get_prpct_from_prpc_id(prpc['id'])
              x_prpcts = []
              prpcts.each() do |prpct|

                @logger.debug("\t\t\tPRPCT = #{prpct.inspect}, class = #{prpct.class}")

                x_prpct = ProductRatePlanChargeTier.new(prpct)
                x_prpcts.push(x_prpct)
              end
              
              x_prpc = ProductRatePlanCharge.new(prpc, x_prpcts)
              x_prpcs.push(x_prpc)
            end

            x_prp = ProductRatePlan.new(prp, x_prpcs)
            x_prps.push(x_prp)
          end

          x_prod = Product.new(prod, x_prps)
          @products.push(x_prod)  
        end      
      end
    end

    def load_from_file(file)
      products = nil
      File.open(file, "rb") do |io|
        products = Marshal.load(io)
      end
      @products = products
    end

    def save_to_file(file)
      File.open(file, "wb") do|io|
        Marshal.dump(@products, io)
      end
    end


    def z_display
      @logger.info("\n\n\n\n                   DISPLAY IN CATALOG              \n\n\n")
      @products.each do |cur|
        cur.print_out($stdout, "#{cur.hash['sKU']}", cur, 0)
        @logger.info("\n")
      end
    end
    
    
    module Display

      def short_class_name(class_name)
        r = class_name.split("::")
        r[r.size - 1]
      end

      def print_out(out, name_extra, entry, tabs)

        tmp = ""
        tabs.times do |t|
          tmp += "\t"
        end
        tmp += "-> "
        tmp += short_class_name(entry.class.to_s)
        tmp += ": "
        tmp += "#{name_extra}: " unless name_extra.nil?

        init = true
        entry.hash.keys.each do |h|
          tmp += ", " unless init
          tmp +=  "#{h} = #{entry.hash[h]}"
          init = false
        end
        out.write("#{tmp}\n")
        if !entry.children.nil?
          entry.children.each() do |cur|
            self.print_out(out, nil, cur, tabs+1)
          end
        end
      end
    end

    class Product #< ZUORA::Product

      module ProductType
        MPP = "mpp"
        LEGACY = "legacy"
        ADDON = "addon"
      end

      include Display

      attr_accessor :hash, :children

      def initialize(hash, prp)
        @hash = hash
        @children = prp
      end
      
      class << self
        def z_create(zuora_client, name, sku, cat, logger=nil)
          
          logger.debug("Creating product #{name} (sku = #{sku}), category = #{cat}") unless logger.nil?

        end
      end
    end

    class ProductRatePlan #< ZUORA::ProductRatePlan

      include Display

      attr_accessor :hash, :children

      def initialize(hash, prpc)
        @hash = hash
        @children = prpc
      end

      def z_create()
      end

    end

    class ProductRatePlanCharge #< ZUORA::ProductRatePlanCharge

      include Display

      attr_accessor :hash, :children

      def initialize(hash,prpct)
        @hash = hash
        @children = prpct
      end

      def z_create()
      end

    end

    class ProductRatePlanChargeTier #< ZUORA::ProductRatePlanChargeTier

      include Display

      attr_accessor :hash, :children

      def initialize(hash)
        @hash = hash
        @children = nil
      end

      def z_create()
      end

    end
  end
end
