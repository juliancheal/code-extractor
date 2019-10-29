lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "code_extractor/version"

Gem::Specification.new do |spec|
  spec.name          = "code-extractor"
  spec.version       = CodeExtractor::VERSION
  spec.authors       = ["Julian Cheal"]

  spec.summary       = "Extracts code from from one repository to another preserving history"
  spec.description   = "Extracts code from from one repository to another preserving history"
  spec.homepage      = "https://github.com/juliancheal/code-extractor"
  spec.license       = "MIT"

  spec.files         = %w[
    bin/code-extractor
    lib/code_extractor.rb
    lib/code_extractor/version.rb
    code-extractor.gemspec
    LICENSE
    README.md
  ]
  spec.bindir        = "bin"
  spec.executables   = ["code-extractor"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 10.0"
end
