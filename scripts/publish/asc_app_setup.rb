#!/usr/bin/env ruby
# App-level ASC setup a fresh record lacks (both 404 until created, and both
# block the review submission with a useless error): price = Free (USA base,
# 0.0 point) and availability = every territory except mainland China (news-app
# licensing, RELEASE_CHECKLIST §4). Idempotent; reads both back.
# Availability CREATE works only while the app has never been live.
require_relative 'asc'
EXCLUDE = %w[CHN].freeze

code, mp = asc('GET', "/appPriceSchedules/#{APP_ID}/manualPrices?include=appPricePoint&limit=5")
free = code == 200 && mp['data'].any? && (mp['included'] || []).any? { |x| x['attributes']['customerPrice'].to_f.zero? }
unless free
  code, pts = asc('GET', "/apps/#{APP_ID}/appPricePoints?filter[territory]=USA&limit=200")
  zero = pts['data'].find { |p| p['attributes']['customerPrice'].to_f.zero? } or abort 'no 0.0 USA price point'
  code, r = asc('POST', '/appPriceSchedules', { data: { type: 'appPriceSchedules', relationships: {
      app: { data: { type: 'apps', id: APP_ID } },
      baseTerritory: { data: { type: 'territories', id: 'USA' } },
      manualPrices: { data: [{ type: 'appPrices', id: '${price-free}' }] } } },
    included: [{ type: 'appPrices', id: '${price-free}', attributes: { startDate: nil },
                 relationships: { appPricePoint: { data: { type: 'appPricePoints', id: zero['id'] } } } }] })
  abort "price schedule #{code} #{JSON.dump(r)}" unless [200, 201].include?(code)
  code, mp = asc('GET', "/appPriceSchedules/#{APP_ID}/manualPrices?include=appPricePoint&limit=5")
end
puts "price READ BACK: #{(mp['included'] || []).map { |x| x['attributes']['customerPrice'] }.inspect}"

code, av = asc('GET', "/apps/#{APP_ID}/appAvailabilityV2?include=territoryAvailabilities&limit[territoryAvailabilities]=1")
if code == 404
  ids = []; url = '/territories?limit=200'
  while url
    c, d = asc('GET', url); ids += d['data'].map { |t| t['id'] }; url = d.dig('links', 'next')
  end
  code, r = asc('POST', '/v2/appAvailabilities', { data: { type: 'appAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: { app: { data: { type: 'apps', id: APP_ID } },
                       territoryAvailabilities: { data: ids.map { |t| { type: 'territoryAvailabilities', id: "${ta-#{t}}" } } } } },
    included: ids.map { |t| { type: 'territoryAvailabilities', id: "${ta-#{t}}", attributes: { available: !EXCLUDE.include?(t) },
                              relationships: { territory: { data: { type: 'territories', id: t } } } } } })
  abort "availability #{code} #{JSON.dump(r)[0, 800]}" unless code == 201
end
code, av = asc('GET', "/apps/#{APP_ID}/appAvailabilityV2")
aid = av['data']['id']
avail = []; url = "/v2/appAvailabilities/#{aid}/territoryAvailabilities?include=territory&limit=200"
while url
  c, d = asc('GET', url)
  d['data'].each { |t| avail << t.dig('relationships', 'territory', 'data', 'id') if t['attributes']['available'] }
  url = d.dig('links', 'next')
end
puts "availability READ BACK: #{avail.length} available, CHN=#{avail.include?('CHN')}, HKG=#{avail.include?('HKG')}, " \
     "MAC=#{avail.include?('MAC')}, TWN=#{avail.include?('TWN')}, newTerritories=#{av['data']['attributes']['availableInNewTerritories']}"
