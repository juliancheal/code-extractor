# ----------------------------------------------- #
#                      Build                      #
# ----------------------------------------------- #

require "rubygems/package_task"

code_extractor_gemspec = eval File.read("code-extractor.gemspec")

Gem::PackageTask.new(code_extractor_gemspec).define


# ----------------------------------------------- #
#                      Test                       #
# ----------------------------------------------- #

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

namespace :test do
  desc "clean test sandbox"
  task :clean do
    sandbox_dir = File.join "test", "tmp"
    rm_rf sandbox_dir
  end


  desc "run a DEBUG test run after cleaning"
  task :debug => :clean do
    ENV["DEBUG"] = "1"
    Rake::Task["test"].invoke
  end
end

task :default => :test
