# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "vault-rails/version"

Gem::Specification.new do |s|
  s.name        = "vault-rails"
  s.version     = Vault::Rails::VERSION
  s.authors     = ["Jordan MacDonald"]
  s.email       = ["jordan.macdonald@greatersudbury.ca"]
  s.homepage    = ""
  s.summary     = 'CoffeeScript collection class for offline use.'
  s.description = 'Store and manage collections of objects without a connection.'

  s.rubyforge_project = "vault-rails"

  s.files         = `git ls-files`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end