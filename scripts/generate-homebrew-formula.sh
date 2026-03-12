#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <version> <arm64_sha256> <x86_64_sha256>" >&2
  exit 1
fi

version="$1"
arm_sha="$2"
intel_sha="$3"

cat <<EOF
class SiftQueue < Formula
  desc "Queue CLI and queue-native task/review substrate"
  homepage "https://github.com/DerekStride/sq"
  version "${version}"
  license "MIT"

  on_arm do
    url "https://github.com/DerekStride/sq/releases/download/v#{version}/sift-queue-v#{version}-aarch64-apple-darwin.tar.gz"
    sha256 "${arm_sha}"
  end

  on_intel do
    url "https://github.com/DerekStride/sq/releases/download/v#{version}/sift-queue-v#{version}-x86_64-apple-darwin.tar.gz"
    sha256 "${intel_sha}"
  end

  def install
    bin.install "sq"
  end

  test do
    queue = testpath/"queue.jsonl"
    output = shell_output("#{bin}/sq add --title test --description hi -q #{queue} --json")
    assert_match '"title":"test"', output
  end
end
EOF
