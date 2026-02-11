#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates test/fixtures/queue.jsonl with sample items covering all source types.
# Run: ruby test/fixtures/generate_queue.rb

require "json"

FIXTURE_DIR = File.expand_path("sources", __dir__)
OUTPUT = File.expand_path("queue.jsonl", __dir__)

def item(id, sources:, metadata: {}, status: "pending")
  now = "2026-02-11T00:00:00Z"
  {
    id: id,
    status: status,
    sources: sources,
    metadata: metadata,
    session_id: nil,
    created_at: now,
    updated_at: now,
  }
end

items = []

# ---------- diff sources (3 items) ----------

items << item("d01", sources: [
  {
    type: "diff",
    path: "lib/sift/client.rb",
    content: <<~DIFF,
      @@ -12,6 +12,8 @@ module Sift
         def initialize(model: nil)
           @model = model
      +    @retries = 3
      +    @timeout = 30
         end

         def prompt(text, session_id: nil)
    DIFF
  },
], metadata: { "pr" => 42, "description" => "Add retry and timeout config to Client" })

items << item("d02", sources: [
  {
    type: "diff",
    path: "app/models/user.rb",
    content: <<~'DIFF',
      @@ -5,7 +5,7 @@ class User < ApplicationRecord
         validates :email, presence: true, uniqueness: true
      -  def full_name
      -    "#{first_name} #{last_name}"
      +  def display_name
      +    "#{first_name} #{last_name}".strip.presence || email
         end
    DIFF
  },
], metadata: { "pr" => 55, "description" => "Rename full_name to display_name with fallback" })

items << item("d03", sources: [
  {
    type: "diff",
    path: "config/routes.rb",
    content: <<~DIFF,
      @@ -10,6 +10,10 @@ Rails.application.routes.draw do
         resources :users, only: [:index, :show]
      +  namespace :api do
      +    namespace :v2 do
      +      resources :webhooks, only: [:create]
      +    end
      +  end
      +
         root "pages#home"
    DIFF
  },
  {
    type: "diff",
    path: "app/controllers/api/v2/webhooks_controller.rb",
    content: <<~DIFF,
      @@ -0,0 +1,18 @@
      +module Api
      +  module V2
      +    class WebhooksController < ApplicationController
      +      skip_before_action :verify_authenticity_token
      +
      +      def create
      +        payload = JSON.parse(request.body.read)
      +        WebhookJob.perform_later(payload)
      +        head :accepted
      +      end
      +    end
      +  end
      +end
    DIFF
  },
], metadata: { "pr" => 61, "description" => "Add v2 webhooks endpoint" })

# ---------- file sources (3 items) ----------

items << item("f01", sources: [
  {
    type: "file",
    path: File.join(FIXTURE_DIR, "user_model.rb"),
  },
], metadata: { "task" => "review", "description" => "Review User model implementation" })

items << item("f02", sources: [
  {
    type: "file",
    path: File.join(FIXTURE_DIR, "config.yml"),
  },
], metadata: { "task" => "audit", "description" => "Audit production config values" })

items << item("f03", sources: [
  {
    type: "file",
    content: <<~'RUBY',
      # frozen_string_literal: true

      class PaymentGateway
        class ChargeError < StandardError; end

        def initialize(api_key:)
          @api_key = api_key
          @client = Stripe::Client.new(api_key)
        end

        def charge(amount_cents:, currency: "usd", customer_id:)
          @client.charges.create(
            amount: amount_cents,
            currency: currency,
            customer: customer_id
          )
        rescue Stripe::CardError => e
          raise ChargeError, "Card declined: #{e.message}"
        end

        def refund(charge_id:, amount_cents: nil)
          params = { charge: charge_id }
          params[:amount] = amount_cents if amount_cents
          @client.refunds.create(params)
        end
      end
    RUBY
  },
], metadata: { "task" => "security-review", "description" => "Review payment gateway for security issues" })

# ---------- text sources (3 items) ----------

items << item("t01", sources: [
  {
    type: "text",
    content: <<~TEXT,
      PR #87: Migrate user sessions to Redis

      We're moving session storage from the database to Redis to reduce
      read latency on every authenticated request. The migration plan:

      1. Deploy Redis-backed session store behind a feature flag
      2. Enable for internal users (1 week soak)
      3. Gradual rollout to 10% -> 50% -> 100%
      4. Remove database session table after 30-day retention window

      Risk: Redis is a single point of failure for sessions. Mitigation:
      we'll use Redis Sentinel for automatic failover.
    TEXT
  },
], metadata: { "category" => "proposal", "author" => "eng-team" })

items << item("t02", sources: [
  {
    type: "text",
    content: <<~TEXT,
      Bug Report: Pagination returns duplicate results

      Steps to reproduce:
      1. GET /api/products?page=1&per_page=25
      2. GET /api/products?page=2&per_page=25
      3. Compare results - items 24 and 25 from page 1 appear again on page 2

      Expected: No duplicates across pages
      Actual: Last 2 items of each page repeat on the next page

      Suspected cause: The ORDER BY clause doesn't include a tiebreaker
      column when sorting by created_at, which has second-level precision.
      Multiple records share the same timestamp.
    TEXT
  },
], metadata: { "category" => "bug", "severity" => "medium" })

items << item("t03", sources: [
  {
    type: "text",
    content: <<~TEXT,
      Release Notes v3.2.0

      New Features:
      - Dark mode support across all pages
      - Bulk export of reports to CSV
      - Two-factor authentication via TOTP

      Bug Fixes:
      - Fixed timezone handling in scheduled reports
      - Corrected rounding errors in invoice totals
      - Resolved race condition in concurrent order processing

      Breaking Changes:
      - API v1 endpoints are now deprecated (removed in v4.0)
      - Minimum Ruby version bumped to 3.2
    TEXT
  },
], metadata: { "category" => "release-notes", "version" => "3.2.0" })

# ---------- transcript sources (3 items) ----------

items << item("x01", sources: [
  {
    type: "transcript",
    content: <<~TRANSCRIPT,
      Human: Can you review this authentication change? We switched from session-based auth to JWT tokens.
      Assistant: I see the change. A few observations:
      1. The JWT secret is loaded from an environment variable - good.
      2. Token expiry is set to 24 hours, which is reasonable.
      3. However, there's no refresh token mechanism. Users will be forced to re-authenticate every 24 hours.
      Human: Good catch on the refresh tokens. We planned to add that in a follow-up PR. Anything else?
      Assistant: One more thing - the token payload includes the user's email. Consider using only the user ID to minimize PII in tokens, since JWTs can be decoded by anyone.
    TRANSCRIPT
  },
], metadata: { "category" => "code-review", "pr" => 103 })

items << item("x02", sources: [
  {
    type: "transcript",
    content: <<~TRANSCRIPT,
      Human: The deploy failed with exit code 137. What does that mean?
      Assistant: Exit code 137 means the process was killed by the OOM (Out of Memory) killer. The container ran out of memory during the build step.
      Human: How do I fix it?
      Assistant: You have a few options:
      1. Increase the container memory limit in your CI config
      2. Optimize the build to use less memory (e.g., reduce parallelism)
      3. Split the build into smaller stages
      System: Build memory limit increased from 2GB to 4GB.
      Human: That fixed it, thanks!
      Assistant: Glad that resolved it. You may want to investigate why memory usage grew - it could indicate a leak in your build tooling that will eventually hit the new limit too.
    TRANSCRIPT
  },
], metadata: { "category" => "debugging", "incident" => "INC-2451" })

items << item("x03", sources: [
  {
    type: "transcript",
    path: File.join(FIXTURE_DIR, "review_conversation.txt"),
  },
], metadata: { "category" => "design-review" })

# ---------- mixed-source item (bonus: shows multi-source navigation) ----------

items << item("m01", sources: [
  {
    type: "text",
    content: "Ticket: Add rate limiting to public API endpoints. Limit: 100 req/min per API key.",
  },
  {
    type: "diff",
    path: "app/middleware/rate_limiter.rb",
    content: <<~'DIFF',
      @@ -0,0 +1,25 @@
      +class RateLimiter
      +  def initialize(app, limit: 100, window: 60)
      +    @app = app
      +    @limit = limit
      +    @window = window
      +  end
      +
      +  def call(env)
      +    key = extract_api_key(env)
      +    return @app.call(env) unless key
      +
      +    count = Redis.current.incr("rate:#{key}")
      +    Redis.current.expire("rate:#{key}", @window) if count == 1
      +
      +    if count > @limit
      +      [429, { "Retry-After" => @window.to_s }, ["Rate limit exceeded"]]
      +    else
      +      @app.call(env)
      +    end
      +  end
      +
      +  private
      +
      +  def extract_api_key(env)
      +    env["HTTP_X_API_KEY"]
      +  end
      +end
    DIFF
  },
  {
    type: "file",
    content: <<~RUBY,
      # frozen_string_literal: true

      RSpec.describe RateLimiter do
        let(:app) { ->(env) { [200, {}, ["OK"]] } }
        let(:limiter) { described_class.new(app, limit: 3, window: 60) }

        it "allows requests under the limit" do
          env = { "HTTP_X_API_KEY" => "test-key" }
          3.times { expect(limiter.call(env).first).to eq(200) }
        end

        it "blocks requests over the limit" do
          env = { "HTTP_X_API_KEY" => "test-key" }
          3.times { limiter.call(env) }
          expect(limiter.call(env).first).to eq(429)
        end
      end
    RUBY
  },
], metadata: { "task" => "implement", "ticket" => "ENG-1234" })

# ---------- write output ----------

File.open(OUTPUT, "w") do |f|
  items.each { |i| f.puts(JSON.generate(i)) }
end

puts "Wrote #{items.length} items to #{OUTPUT}"
