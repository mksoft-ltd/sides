#!/usr/bin/env ruby
# Upload ios/fastlane/screenshots/<locale>/*.png to the current editable iOS
# appStoreVersion, one set per display type, via the raw API with server-side
# read-back (deliver appends duplicates under a "Successfully uploaded" line).
# Files are grouped by pixel size: 1320x2868 -> APP_IPHONE_67 (6.9"),
# 2752x2064 / 2064x2752 -> APP_IPAD_PRO_3GEN_129 (13"). Existing images in a set
# are deleted first; order follows file name.
require_relative 'asc'
require 'digest'

DIR = File.expand_path('../../ios/fastlane/screenshots', __dir__)
TYPES = { [1320, 2868] => 'APP_IPHONE_67', [2752, 2064] => 'APP_IPAD_PRO_3GEN_129',
          [2064, 2752] => 'APP_IPAD_PRO_3GEN_129' }.freeze

def png_size(path)
  File.binread(path, 24)[16, 8].unpack('NN')
end

code, d = asc('GET', "/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED")
abort "versions #{code}" unless code == 200 && d['data'].any?
vid = d['data'].first['id']
code, locs = asc('GET', "/appStoreVersions/#{vid}/appStoreVersionLocalizations")
fails = 0
Dir["#{DIR}/*"].select { |p| File.directory?(p) }.sort.each do |ldir|
  locale = File.basename(ldir)
  loc = locs['data'].find { |l| l['attributes']['locale'] == locale } or abort "no #{locale} localization on #{vid}"
  groups = Dir["#{ldir}/*.png"].sort.group_by do |f|
    TYPES.fetch(png_size(f)) { abort "#{f}: unexpected size #{png_size(f).join('x')}" }
  end
  code, sets = asc('GET', "/appStoreVersionLocalizations/#{loc['id']}/appScreenshotSets")
  groups.each do |type, files|
    set = sets['data'].find { |s| s['attributes']['screenshotDisplayType'] == type }
    if set
      code, ex = asc('GET', "/appScreenshotSets/#{set['id']}/appScreenshots")
      ex['data'].each { |s| asc('DELETE', "/appScreenshots/#{s['id']}") }
      set_id = set['id']
    else
      code, r = asc('POST', '/appScreenshotSets', { data: { type: 'appScreenshotSets',
        attributes: { screenshotDisplayType: type },
        relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc['id'] } } } } })
      abort "create set #{code} #{r}" unless code == 201
      set_id = r['data']['id']
    end
    ids = files.map do |path|
      bytes = File.binread(path)
      code, r = asc('POST', '/appScreenshots', { data: { type: 'appScreenshots',
        attributes: { fileSize: bytes.bytesize, fileName: File.basename(path) },
        relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set_id } } } } })
      abort "reserve #{path} #{code} #{r}" unless code == 201
      sid = r['data']['id']
      r['data']['attributes']['uploadOperations'].each do |op|
        uri = URI(op['url']); put = Net::HTTP::Put.new(uri)
        op['requestHeaders'].each { |h| put[h['name']] = h['value'] }
        put.body = bytes[op['offset'], op['length']]
        resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 300) { |h| h.request(put) }
        abort "PUT #{path} #{resp.code}" unless resp.code.to_i.between?(200, 299)
      end
      code, r = asc('PATCH', "/appScreenshots/#{sid}", { data: { type: 'appScreenshots', id: sid,
        attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) } } })
      abort "commit #{path} #{code} #{r}" unless code == 200
      sid
    end
    asc('PATCH', "/appScreenshotSets/#{set_id}/relationships/appScreenshots",
        { data: ids.map { |i| { type: 'appScreenshots', id: i } } })
    code, after = asc('GET', "/appScreenshotSets/#{set_id}/appScreenshots")
    names = after['data'].map { |s| s['attributes']['fileName'] }
    ok = names == files.map { |f| File.basename(f) }
    fails += 1 unless ok
    puts "#{ok ? 'READ BACK' : 'MISMATCH'} #{locale} #{type}: #{names.length} (#{names.join(', ')})"
  end
end
exit(fails.zero? ? 0 : 1)
