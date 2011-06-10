$:.unshift File.join(File.dirname(__FILE__),'.')

require 'rubygems'
require 'optparse'
require 'logger'

require "util"
require "config"
require "csv"
require "catalog"
require "zuora"
require "validation"

module CatalogTool

  class CommandParserException < Exception
  end

  class CommandAction
    extend Enum

    # Fetch catalog into dump (env, dump_file, csv_file)
    self.add_enum(:FETCH, 0)

    # Validate CSV against zuora dump (dump_file, csv_file)
    self.add_enum(:VALIDATE, 1)

    # Sync CSV into Zuora (env, csv_file)
    self.add_enum(:SYNC, 2)


    def CommandAction.all
      all = []
      CommandAction.each do |a|
        all << a.value
      end
      all.join(",")
    end
  end

  class CommandParser

    attr_reader :options, :action, :csv_file, :dump_file, :env, :config, :log_level

    def initialize
      @options = {}
    end

    def parse(args)
      optparse = OptionParser.new do |opts|
        opts.banner = "Usage: ri_catalog.rb [options]"

        opts.separator ""

        #
        # Actions
        #
        opts.on("-F", "--fetch",
        "Fetch catalog from zuora") { @options[:fetch] = true }
        opts.on("-V", "--validate-csv",
        "Validate CSV against zuora catalog (dump) ") { @options[:validate] = true }
        opts.on("-S", "--sync",
        "Sync CSV against zuora catalog") { @options[:sync] = true }

        #
        # Config
        #
        opts.on("-e", "--environment ENV",
        "Environment (xno, sandbox, dump))") do |e|
          @options[:env] = e
        end

        opts.on("-k", "--config config",
        "Configuration file") do |k|
          @options[:config] = k
        end

        opts.on("-s", "--sanity validation_config",
        "Validation callback file") do |s|
          @options[:sanity] = s
        end        

        opts.on("-x", "--push-through",
        "Disable checking when syncing") { @options[:push_through] = true }

        #
        # Dump, csv and logging
        #
        opts.on("-c", "--csv CSV_FILE",
        "location of csv file (output for fetch and input for validate and and sync)") { |c| @options[:csv] = c }
        opts.on("-d", "--dump DUMP_FILE",
        "location of dump file (output for fetch and input for validate and and sync)") { |d| @options[:dump] = d }
        opts.on("-l", "--log-level LOG_LEVEL", "Specifies log level") { |l| @options[:log_level] = l }
      end

      optparse.parse!(args)
      validate_args
    end



    def validate_args

      #      p @options

      nb_actions = 0
      if @options[:fetch]
        nb_actions += 1
        @action = CommandAction::FETCH
      end

      if @options[:validate]
        nb_actions += 1
        @action = CommandAction::VALIDATE
      end

      if @options[:sync]
        nb_actions += 1
        @action = CommandAction::SYNC
      end

      if nb_actions != 1
        raise CommandParserException, "Need to specify one and only one action in #{CommandAction.all}"
      end

      @env = @options[:env]
      if @env.nil?
        raise CommandParserException, "Need to specify environment"
      end

      @config = @options[:config]
      if @config.nil?
        raise CommandParserException, "Need to specify a configuration file with one entry for each environment"
      end

      # Will raise an exception if invalid
      config = Config.new(@env, @config, nil)


      case @action
      when CommandAction::FETCH
        validate_args_fetch
      when CommandAction::VALIDATE
        validate_args_validate
      when CommandAction::SYNC
        validate_args_sync
      end


      if ! @options[:log_level].nil?
        case @options[:log_level]
        when "DEBUG"
          @log_level = Logger::DEBUG
        when "INFO"
          @log_level = Logger::INFO
        when "WARN"
          @log_level = Logger::WARN
        when "ERR"
          @log_level = Logger::ERR
        end
      else
        @log_level = Logger::INFO
      end
    end

    def validate_args_fetch

      @csv_file = @options[:csv]
      @dump_file = @options[:dump]

      if @csv_file.nil? || @dump_file.nil?
        raise CommandParserException, "Need to specify both output csv and dump file for action #{@action.value}"
      end
    end

    def validate_args_validate
      @csv_file = @options[:csv]
      @dump_file = @options[:dump]

      if @csv_file.nil? || @dump_file.nil?
        raise CommandParserException, "Need to specify both output csv and dump file for action #{@action.value}"
      end

    end

    def validate_args_sync
      @csv_file = @options[:csv]
      @dump_file = @options[:dump] 
      if @csv_file.nil? || @dump_file.nil?
        raise CommandParserException, "Need to specify both output csv and dump file for action #{@action.value}"
      end     
    end

    def run_fetch(logger)

      catalog = nil
      if @env == "dump"
        catalog = ZuoraCatalog.new(nil, logger)
        catalog.load_from_file(@dump_file)
      else
        config = Config.new(@env, @config, logger)
        zuora_client = Zuora::API.new(config)
        catalog = ZuoraCatalog.new(zuora_client, logger)
        catalog.z_fetch
        catalog.save_to_file(@dump_file)
      end

      csv_writer = CatalogTool::CSVCatalogWriter.new(logger, Zuora.private_fields, catalog)
      csv_writer.export_to_file(@csv_file)
    end

    def run_validate(logger)

      if @env !=  "dump"
        raise CommandParserException, "validate should only be used with dump mode"
      end

      catalog = ZuoraCatalog.new(nil, logger)
      catalog.load_from_file(@dump_file)

      csv_ref = CSVCatalog.new(logger, Zuora.private_fields)
      csv_ref.extract_from_z_catalog(catalog)

      csv_new = CSVCatalogReader.new(logger, @options[:sanity], Zuora.private_fields, @csv_file)
      validator = Validator.new(logger)
      validator.cross_validation_from_csvs(csv_ref, csv_new)
    end

    def run_sync(logger)

      if @env ==  "dump"
        raise CommandParserException, "Sync needs to specify a target environment"
      end

      catalog = ZuoraCatalog.new(nil, logger)
      catalog.load_from_file(@dump_file)

      csv_ref = CSVCatalog.new(logger, Zuora.private_fields)
      csv_ref.extract_from_z_catalog(catalog)

      csv_new = CSVCatalogReader.new(logger, @options[:sanity], Zuora.private_fields, @csv_file)

      validator = Validator.new(logger)
      hash_diff = validator.cross_validation_from_csvs(csv_ref, csv_new)      

      config = Config.new(@env, @config, logger)
      zuora_client = Zuora::API.new(config)

      validator.sync_from_diff(hash_diff, zuora_client, true, @options[:push_through])

    end

    def run
      logger = Logger.new(STDOUT)
      logger.level = @log_level
      logger.info("Start with action = #{@action.value} csv_file = #{@csv_file} dump_file = #{@dump_file} env = #{@env} log_level = #{@log_level}")

      case @action
      when CommandAction::FETCH
        run_fetch(logger)
      when CommandAction::VALIDATE
        run_validate(logger)
      when CommandAction::SYNC
        run_sync(logger)
      end
    end
  end
end

