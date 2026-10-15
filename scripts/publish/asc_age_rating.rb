#!/usr/bin/env ruby
# Apply ios/fastlane/rating.json to the app's ageRatingDeclaration (it hangs off
# the editable appInfo, not the version) and read it back.
require_relative 'asc'
RATING = JSON.parse(File.read(File.expand_path('../../ios/fastlane/rating.json', __dir__)))
attrs = RATING.reject { |k, _| k.start_with?('_') }

code, d = asc('GET', "/apps/#{APP_ID}/appInfos")
abort "appInfos #{code}" unless code == 200
info = d['data'].reject { |x| x['attributes']['state'] == 'READY_FOR_DISTRIBUTION' }.first or abort 'no editable appInfo'
code, decl = asc('GET', "/appInfos/#{info['id']}/ageRatingDeclaration")
abort "declaration read #{code} #{decl}" unless code == 200
did = decl['data']['id']
code, res = asc('PATCH', "/ageRatingDeclarations/#{did}",
                { data: { type: 'ageRatingDeclarations', id: did, attributes: attrs } })
abort "PATCH #{code} #{JSON.pretty_generate(res)}" unless code == 200
got = res['data']['attributes']
diff = attrs.reject { |k, v| got[k] == v }
abort "READ BACK MISMATCH #{diff.keys.inspect}" unless diff.empty?
puts "age rating applied to #{did}: #{attrs.length} attributes read back identical"
code, d = asc('GET', "/appInfos/#{info['id']}")
puts "appStoreAgeRating=#{d.dig('data', 'attributes', 'appStoreAgeRating').inspect}"
