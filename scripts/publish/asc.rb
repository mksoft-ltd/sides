#!/usr/bin/env ruby
# Minimal App Store Connect API helper (ES256 JWT -> bearer token).
# Mirrors scripts/play.rb. Several ASC operations this repo needs have no
# working fastlane action (price schedules, age rating, IAP offers, submission
# preflight), so they are driven straight against the REST API from here.
require 'jwt'
require 'net/http'
require 'json'
require 'uri'
require 'openssl'

KEY_ID    = ENV.fetch('ASC_KEY_ID')
ISSUER_ID = ENV.fetch('ASC_ISSUER_ID')
KEY_PATH  = File.expand_path(ENV.fetch('ASC_KEY_PATH'))
APP_ID    = ENV['ASC_APP_ID'] || '6822909350'

def asc_token
  key = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
  now = Time.now.to_i
  JWT.encode({ iss: ISSUER_ID, aud: 'appstoreconnect-v1', exp: now + 1200, iat: now },
             key, 'ES256', { kid: KEY_ID, typ: 'JWT' })
end

ASC_TOK = asc_token

# path may be "/v1/apps/..." or a bare "/apps/..." (v1 assumed) or a full URL.
def asc(method, path, body = nil)
  url = if path.start_with?('http')
          path
        elsif path.start_with?('/v1/', '/v2/', '/v3/')
          "https://api.appstoreconnect.apple.com#{path}"
        else
          "https://api.appstoreconnect.apple.com/v1#{path}"
        end
  uri = URI(url)
  klass = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post,
            'PUT' => Net::HTTP::Put, 'PATCH' => Net::HTTP::Patch,
            'DELETE' => Net::HTTP::Delete }.fetch(method)
  r = klass.new(uri)
  r['Authorization'] = "Bearer #{ASC_TOK}"
  r['Content-Type'] = 'application/json'
  r.body = JSON.dump(body) if body
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 300) { |h| h.request(r) }
  parsed = begin
    res.body.nil? || res.body.empty? ? nil : JSON.parse(res.body)
  rescue StandardError
    res.body
  end
  [res.code.to_i, parsed]
end

if __FILE__ == $0
  code, data = asc(ARGV[0], ARGV[1], ARGV[2] ? JSON.parse(ARGV[2]) : nil)
  puts "HTTP #{code}"
  puts JSON.pretty_generate(data) if data
end
