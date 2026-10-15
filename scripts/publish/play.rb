#!/usr/bin/env ruby
# Minimal Google Play Developer API helper (service-account JWT -> access token).
require 'jwt'
require 'net/http'
require 'json'
require 'uri'

SA = JSON.parse(File.read(ENV.fetch('PLAY_JSON_KEY')))
PKG = ENV['PLAY_PACKAGE'] || 'com.froggyeye.sides'

def access_token
  now = Time.now.to_i
  claims = {
    iss: SA['client_email'],
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3000, iat: now
  }
  key = OpenSSL::PKey::RSA.new(SA['private_key'])
  assertion = JWT.encode(claims, key, 'RS256', { kid: SA['private_key_id'] })
  uri = URI('https://oauth2.googleapis.com/token')
  res = Net::HTTP.post_form(uri, 'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                                 'assertion' => assertion)
  JSON.parse(res.body).fetch('access_token') { raise "token error: #{res.body}" }
end

TOK = access_token

def req(method, path, body = nil)
  base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{PKG}"
  uri = URI(path.start_with?('http') ? path : "#{base}#{path}")
  klass = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post,
            'PUT' => Net::HTTP::Put, 'PATCH' => Net::HTTP::Patch,
            'DELETE' => Net::HTTP::Delete }[method]
  r = klass.new(uri)
  r['Authorization'] = "Bearer #{TOK}"
  r['Content-Type'] = 'application/json'
  r.body = JSON.dump(body) if body
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(r) }
  parsed = begin
    res.body.nil? || res.body.empty? ? nil : JSON.parse(res.body)
  rescue StandardError
    res.body
  end
  [res.code.to_i, parsed]
end

if __FILE__ == $0
  code, data = req(ARGV[0], ARGV[1], ARGV[2] ? JSON.parse(ARGV[2]) : nil)
  puts "HTTP #{code}"
  puts JSON.pretty_generate(data) if data
end
