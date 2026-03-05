# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Build Rust sq binary"
task :build_sq_rust do
  unless ENV["SKIP_RUST"]
    sh "cd sq-rust && cargo build --release"
    cp "target/release/sq", "exe/sq.rust"
  end
end

desc "Run Rust tests"
task :test_sq_rust do
  unless ENV["SKIP_RUST"]
    sh "cd sq && cargo test"
  end
end

task default: [:test, :test_sq_rust]
