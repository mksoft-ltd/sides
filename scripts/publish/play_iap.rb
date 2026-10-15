#!/usr/bin/env ruby
# Create/update the Play one-time product com.froggyeye.sides.adfree and
# activate its purchase option, then read it back.
# Price: convertRegionPrices fed GBP 2.49 TAX-EXCLUSIVE (= GBP 2.99 shelf,
# house-facts §18), regionsVersion taken from the conversion; US overridden to
# USD 2.99. legacyCompatible so the in_app_purchase plugin resolves it.
# Play refuses creation until an artifact declaring BILLING is in a track.
require_relative 'play'

PID = 'com.froggyeye.sides.adfree'
OPT = 'adfree-buy'
die = ->(s, c, d) { abort "FAILED #{s}: HTTP #{c}\n#{JSON.pretty_generate(d) rescue d}" }
money = ->(cur, amount) { u, n = format('%.2f', amount).split('.'); { currencyCode: cur, units: u, nanos: n.to_i * 10_000_000 } }

code, conv = req('POST', '/pricing:convertRegionPrices', { price: money.('GBP', 2.49) })
die.('convertRegionPrices', code, conv) unless code == 200
regions = conv['convertedRegionPrices'].values.map do |r|
  price = r['regionCode'] == 'US' ? money.('USD', 2.99) : r['price']
  { regionCode: r['regionCode'], price: price, availability: 'AVAILABLE' }
end
gb = conv['convertedRegionPrices']['GB']['price']
puts "convert: GB #{gb['units']}.#{gb['nanos'].to_i / 10_000_000} #{gb['currencyCode']}, regions=#{regions.length}, version=#{conv.dig('regionVersion', 'version')}"
abort "GB converted to #{gb.inspect}, want 2.99" unless gb['units'] == '2' && gb['nanos'].to_i == 990_000_000

product = { packageName: PKG, productId: PID,
  listings: [{ languageCode: 'en-GB', title: 'Remove ads', description: 'Removes the banner ads for good. One-time purchase, no subscription.' },
             { languageCode: 'en-US', title: 'Remove ads', description: 'Removes the banner ads for good. One-time purchase, no subscription.' }],
  purchaseOptions: [{ purchaseOptionId: OPT, buyOption: { legacyCompatible: true, multiQuantityEnabled: false },
                      regionalPricingAndAvailabilityConfigs: regions }] }
code, r = req('POST', '/oneTimeProducts:batchUpdate', { requests: [{ oneTimeProduct: product,
  updateMask: 'listings,purchaseOptions', allowMissing: true,
  regionsVersion: { version: conv.dig('regionVersion', 'version') } }] })
die.('batchUpdate', code, r) unless code == 200
code, r = req('POST', "/oneTimeProducts/#{PID}/purchaseOptions:batchUpdateStates", { requests: [
  { activatePurchaseOptionRequest: { packageName: PKG, productId: PID, purchaseOptionId: OPT } }] })
die.('activate', code, r) unless code == 200
code, g = req('GET', "/oneTimeProducts/#{PID}")
die.('read back', code, g) unless code == 200
o = g['purchaseOptions'].first
cfg = o['regionalPricingAndAvailabilityConfigs'].to_h { |c| [c['regionCode'], c['price']] }
puts "READ BACK #{PID}: option=#{o['purchaseOptionId']} state=#{o['state']} legacyCompatible=#{o.dig('buyOption', 'legacyCompatible')} " \
     "GB=#{cfg['GB']&.values_at('units', 'nanos')&.join('.')} US=#{cfg['US']&.values_at('units', 'nanos')&.join('.')} " \
     "listings=#{g['listings'].map { |l| l['languageCode'] }.inspect}"
