$:.unshift File.join(File.dirname(__FILE__),'.')

require 'rubygems'
require 'logger'
require 'yaml'
require 'zuora_client'


module CatalogTool

  
  class ConfigException < Exception
  end

  class Config

    
    attr_reader :env, :logger, :config_file, :catalog_config

    def initialize(env, config_file, logger)
      @logger = logger
      if ! ENV['CATALOG_ENV'].nil?
        @env = ENV['CATALOG_ENV']
        @logger.info("Using environment from environment variable CATALOG_ENV : env = #{@env}") unless @logger.nil?
      else
        @env = env
        @logger.info("Config with env =  #{@env}")  unless @logger.nil?
      end

      @config_file = config_file
      if !File.exists?(@config_file)
        raise IOError, "Can't find config file #{@config_file}"
      end

      @catalog_config = YAML.load_file(@config_file)[@env]
      if @catalog_config.nil?
        raise ConfigException, "Config for env #{@env} does not exist"
      end
    end

    def is_env_dump?
      @catalog_config['zuora']['is_dump']      
    end

    def zuora_user
      @catalog_config['zuora']['username']
    end

    def zuora_pwd
      @catalog_config['zuora']['password']
    end

    def zuora_url
      @catalog_config['zuora']['url']
    end
  end  

end
