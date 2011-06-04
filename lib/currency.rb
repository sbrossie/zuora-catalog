$:.unshift File.join(File.dirname(__FILE__),'.')

require "util"

module CatalogTool

  class Currency
    extend Enum

    self.add_enum(:USD, 0) 
    self.add_enum(:EUR, 1) 
    self.add_enum(:GBP, 2) 
    self.add_enum(:AUD, 3) 
    self.add_enum(:BRL, 4)
    self.add_enum(:MXN, 5) 
  end
end

