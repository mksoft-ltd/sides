#!/usr/bin/env ruby
# Create / complete the non-consumable com.froggyeye.sides.adfree on App Store
# Connect, idempotently: IAP -> en-GB + en-US localisations -> price schedule
# (base GBR GBP 2.99, USA set explicitly to USD 2.99, rest equalised) ->
# availability (every territory except mainland China, plus new territories) ->
# App Review screenshot (iap_review_settings.png, the iOS Settings capture at
# GBP 2.99). Every step is read back. Submission is NOT done here (house-facts
# §15: add it from the IAP's own page into the version's draft submission).
require_relative 'asc'
require 'digest'

ROOT = File.expand_path('../..', __dir__)
PID = 'com.froggyeye.sides.adfree'
SHOT = "#{ROOT}/store_assets/screenshots/raw/iap_review_settings.png"
LOCS = { 'en-GB' => 'Removes the banner ads for good. One-time purchase.',
         'en-US' => 'Removes the banner ads for good. One-time purchase.' }.freeze
NAME = 'Remove ads'
PRICES = { 'GBR' => '2.99', 'USA' => '2.99' }.freeze
EXCLUDE = %w[CHN].freeze
die = ->(s, c, d) { abort "FAILED #{s}: HTTP #{c}\n#{JSON.pretty_generate(d) rescue d}" }

# 1. IAP
code, d = asc('GET', "/apps/#{APP_ID}/inAppPurchasesV2?filter[productId]=#{PID}")
iap = d['data'].first
unless iap
  code, d = asc('POST', '/v2/inAppPurchases', { data: { type: 'inAppPurchases',
    attributes: { name: 'Ad-free', productId: PID, inAppPurchaseType: 'NON_CONSUMABLE', familySharable: false,
                  reviewNote: 'Removes the AdMob banner shown at the bottom of the list and story screens. ' \
                              'No content is gated. Settings > Ads > "Remove ads" starts the purchase; ' \
                              '"Restore purchases" is underneath.' },
    relationships: { app: { data: { type: 'apps', id: APP_ID } } } } })
  die.('create IAP', code, d) unless code == 201
  iap = d['data']
  puts "created IAP #{iap['id']}"
end
IAP = iap['id']
puts "IAP #{IAP} #{PID}"

# 2. localisations
code, d = asc('GET', "/v2/inAppPurchases/#{IAP}/inAppPurchaseLocalizations")
have = d['data'].to_h { |l| [l['attributes']['locale'], l] }
LOCS.each do |loc, desc|
  attrs = { name: NAME, description: desc }
  if have[loc]
    code, r = asc('PATCH', "/inAppPurchaseLocalizations/#{have[loc]['id']}",
                  { data: { type: 'inAppPurchaseLocalizations', id: have[loc]['id'], attributes: attrs } })
    die.("patch loc #{loc}", code, r) unless code == 200
  else
    code, r = asc('POST', '/inAppPurchaseLocalizations', { data: { type: 'inAppPurchaseLocalizations',
      attributes: attrs.merge(locale: loc),
      relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: IAP } } } } })
    die.("create loc #{loc}", code, r) unless code == 201
  end
end

# 3. price schedule
def point(terr, want)
  url = "/v2/inAppPurchases/#{IAP}/pricePoints?filter[territory]=#{terr}&limit=200"
  while url
    code, d = asc('GET', url)
    abort "price points #{terr} #{code}" unless code == 200
    hit = d['data'].find { |p| p['attributes']['customerPrice'] == want }
    return hit['id'] if hit
    url = d.dig('links', 'next')
  end
  abort "no #{want} point in #{terr}"
end
def manual_prices
  code, mp = asc('GET', "/inAppPurchasePriceSchedules/#{IAP}/manualPrices?include=inAppPurchasePricePoint,territory&limit=50")
  return {} unless code == 200
  inc = (mp['included'] || []).to_h { |x| [[x['type'], x['id']], x] }
  mp['data'].to_h do |p|
    pp = p.dig('relationships', 'inAppPurchasePricePoint', 'data', 'id')
    [p.dig('relationships', 'territory', 'data', 'id'), inc[['inAppPurchasePricePoints', pp]]&.dig('attributes', 'customerPrice')]
  end
end
if manual_prices.slice(*PRICES.keys) != PRICES
  body = { data: { type: 'inAppPurchasePriceSchedules', relationships: {
             inAppPurchase: { data: { type: 'inAppPurchases', id: IAP } },
             baseTerritory: { data: { type: 'territories', id: 'GBR' } },
             manualPrices: { data: PRICES.keys.map { |t| { type: 'inAppPurchasePrices', id: "${price-#{t}}" } } } } },
           included: PRICES.map { |t, v| { type: 'inAppPurchasePrices', id: "${price-#{t}}", attributes: { startDate: nil },
             relationships: { inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: point(t, v) } },
                              territory: { data: { type: 'territories', id: t } } } } } }
  code, r = asc('POST', '/inAppPurchasePriceSchedules', body)
  die.('price schedule', code, r) unless [200, 201].include?(code)
end
got = manual_prices
abort "PRICE READ BACK MISMATCH #{got.inspect}" unless got.slice(*PRICES.keys) == PRICES
puts "price READ BACK #{got.inspect}"

# 4. availability
code, d = asc('GET', '/territories?limit=200')
terrs = d['data'].map { |t| t['id'] } - EXCLUDE
def avail_terrs
  ids = []; url = "/inAppPurchaseAvailabilities/#{IAP}/availableTerritories?limit=200"
  while url
    code, d = asc('GET', url)
    return [] unless code == 200
    ids += d['data'].map { |t| t['id'] }; url = d.dig('links', 'next')
  end
  ids
end
current = avail_terrs
if current.sort != terrs.sort
  code, r = asc('POST', '/inAppPurchaseAvailabilities', { data: { type: 'inAppPurchaseAvailabilities',
    attributes: { availableInNewTerritories: true },
    relationships: { inAppPurchase: { data: { type: 'inAppPurchases', id: IAP } },
                     availableTerritories: { data: terrs.map { |t| { type: 'territories', id: t } } } } } })
  die.('availability', code, r) unless code == 201
  current = avail_terrs
end
puts "availability READ BACK #{current.length} territories, CHN=#{current.include?('CHN')}, GBR=#{current.include?('GBR')}, USA=#{current.include?('USA')}"

# 5. review screenshot (compare checksum: ASC renames the file to SOURCE)
bytes = File.binread(SHOT); md5 = Digest::MD5.hexdigest(bytes)
code, s = asc('GET', "/v2/inAppPurchases/#{IAP}/appStoreReviewScreenshot")
cur = code == 200 ? s['data'] : nil
if cur.nil? || cur['attributes']['sourceFileChecksum'] != md5
  asc('DELETE', "/inAppPurchaseAppStoreReviewScreenshots/#{cur['id']}") if cur
  code, r = asc('POST', '/inAppPurchaseAppStoreReviewScreenshots', { data: { type: 'inAppPurchaseAppStoreReviewScreenshots',
    attributes: { fileName: File.basename(SHOT), fileSize: bytes.bytesize },
    relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: IAP } } } } })
  die.('reserve screenshot', code, r) unless code == 201
  sid = r['data']['id']
  r['data']['attributes']['uploadOperations'].each do |op|
    uri = URI(op['url']); put = Net::HTTP::Put.new(uri)
    op['requestHeaders'].each { |h| put[h['name']] = h['value'] }
    put.body = bytes[op['offset'], op['length']]
    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(put) }
    abort "screenshot PUT #{resp.code}" unless resp.code.to_i.between?(200, 299)
  end
  code, r = asc('PATCH', "/inAppPurchaseAppStoreReviewScreenshots/#{sid}", { data: { type: 'inAppPurchaseAppStoreReviewScreenshots',
    id: sid, attributes: { uploaded: true, sourceFileChecksum: md5 } } })
  die.('commit screenshot', code, r) unless code == 200
end
sleep 5
code, s = asc('GET', "/v2/inAppPurchases/#{IAP}/appStoreReviewScreenshot")
puts "review screenshot READ BACK checksum_match=#{s.dig('data', 'attributes', 'sourceFileChecksum') == md5} " \
     "state=#{s.dig('data', 'attributes', 'assetDeliveryState', 'state')}"
code, l = asc('GET', "/v2/inAppPurchases/#{IAP}/inAppPurchaseLocalizations")
l['data'].each { |x| a = x['attributes']; puts "loc READ BACK #{a['locale']}: #{a['name'].inspect} / #{a['description'].inspect} (#{a['description'].length})" }
code, d = asc('GET', "/v2/inAppPurchases/#{IAP}")
puts "IAP state=#{d['data']['attributes']['state']}"
