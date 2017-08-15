# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "git_sme/version"

Gem::Specification.new do |spec|
  spec.name          = "git_sme"
  spec.version       = GitSme::VERSION
  spec.authors       = ["Shahbaz Javeed"]
  spec.email         = ["sjaveed@gmail.com"]

  spec.summary       = %q{Identify subject matter experts by analyzing your git repository}
  spec.description   = %q{Analyze your git repository and determine subject matter experts by identifying everyone who has touched a file with preference given to recent touches}
  spec.homepage      = "https://github.com/sjaveed/git_sme"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.2"

  spec.add_dependency 'ruby-progressbar'
  spec.add_dependency 'rugged'
  spec.add_dependency 'thor'
end
