require 'rubygems'
require 'tmpdir'
require 'rake'
require 'rake/testtask'
require 'rake/clean'
require 'rake/gempackagetask'


THIS_FILE = File.expand_path(__FILE__)
PWD = File.dirname(THIS_FILE)
RUBY = File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name'])

PACKAGE_NAME = 'zuora-catalog'
GEM_VERSION = '1.0.0'

task :default => ['test:validation']

#
# Tests
#
namespace :test do
  Rake::TestTask.new(:all) do |t|
    t.pattern = 'test/test*.rb'
    t.libs << 'test'
    t.warning = true
  end


  Rake::TestTask.new(:validation) do |t|
    t.test_files = FileList['test/test_validation.rb'] 
    t.libs << 'test'
    t.warning = true
  end

  Rake::TestTask.new(:zuora) do |t|
    t.test_files = FileList['test/test_sync.rb'] 
    t.libs << 'test'
    t.warning = true
  end
end


#
# Gemfile
#

spec = Gem::Specification.new do |s|
  s.name = PACKAGE_NAME
  s.version = GEM_VERSION
  s.author = "Ning, Inc."
  s.email = "stephane@ning.com"
  s.homepage = "http://github.com/ning/zuora-catalog"
  s.platform = Gem::Platform::RUBY
  s.summary = "Zuora catalog is a ruby client used to manage zuora catalog information based on CSV representation -- edited from excel"
  s.files =  FileList["lib/**/*.rb", "test/*.rb", "test/data/*.csv", "bin/*", "conf/environment_sample.yml", "README.rdoc", "Rakefile", "LICENSE.txt"]
  s.executables = FileList["zuora-catalog"]
  s.require_path = "lib"
  s.add_dependency("json", ">= 1.5.1")
  s.add_dependency("json_pure", ">= 1.5.1")  
  s.add_dependency("zuora4r", ">= 1.2.1")  
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_zip = false
  pkg.need_tar = true
end
