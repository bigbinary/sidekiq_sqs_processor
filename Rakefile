
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Build documentation"
task :docs do
  system "yard"
end

