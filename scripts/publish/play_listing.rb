#!/usr/bin/env ruby
# Write the Play store listing from android/fastlane/metadata/android/<locale>/
# through the raw edits API, then read it back through a fresh edit.
#   --text         title / short / full description for every local locale
#   --graphics     hi-res icon (store_assets/icon_512.png) + feature graphic
#   --screenshots  images/phoneScreenshots + images/tenInchScreenshots (replace)
#   --dry-run      build the edit, then delete it instead of committing
# Not supply: a metadata-only supply run aborts on an app with no release yet.
require_relative 'play'

ROOT = File.expand_path('../..', __dir__)
META = "#{ROOT}/android/fastlane/metadata/android"
LOCALES = Dir["#{META}/*"].select { |d| File.directory?(d) }.map { |d| File.basename(d) }.sort
DRY = ARGV.include?('--dry-run')
TEXT = ARGV.include?('--text'); GFX = ARGV.include?('--graphics'); SHOTS = ARGV.include?('--screenshots')
abort 'pass --text, --graphics and/or --screenshots' unless TEXT || GFX || SHOTS
GRAPHICS = { 'icon' => "#{ROOT}/store_assets/icon_512.png",
             'featureGraphic' => "#{ROOT}/store_assets/feature_graphic.png" }.freeze
SHOT_TYPES = %w[phoneScreenshots tenInchScreenshots].freeze

def upload_image(eid, lang, type, path)
  uri = URI("https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/#{PKG}" \
            "/edits/#{eid}/listings/#{lang}/#{type}?uploadType=media")
  bytes = File.binread(path)
  r = Net::HTTP::Post.new(uri)
  r['Authorization'] = "Bearer #{TOK}"; r['Content-Type'] = 'image/png'; r.body = bytes
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 600) { |h| h.request(r) }
  [res.code.to_i, (JSON.parse(res.body) rescue res.body)]
end

code, edit = req('POST', '/edits'); abort "edit #{code} #{edit}" unless code == 200
eid = edit['id']
LOCALES.each do |lang|
  d = "#{META}/#{lang}"
  if TEXT
    body = { language: lang, title: File.read("#{d}/title.txt").strip,
             shortDescription: File.read("#{d}/short_description.txt").strip,
             fullDescription: File.read("#{d}/full_description.txt").strip }
    v = "#{d}/video.txt"; body[:video] = File.read(v).strip if File.exist?(v) && !File.read(v).strip.empty?
    code, r = req('PUT', "/edits/#{eid}/listings/#{lang}", body)
    abort "listing #{lang} #{code} #{JSON.dump(r)}" unless code == 200
    puts "#{lang}: listing text written"
  end
  if GFX
    GRAPHICS.each do |type, path|
      abort "missing #{path}" unless File.exist?(path)
      req('DELETE', "/edits/#{eid}/listings/#{lang}/#{type}")
      code, r = upload_image(eid, lang, type, path)
      abort "#{lang} #{type} #{code} #{JSON.dump(r)}" unless code == 200
      puts "#{lang}: #{type} uploaded"
    end
  end
  next unless SHOTS
  SHOT_TYPES.each do |type|
    files = Dir["#{d}/images/#{type}/*.png"].sort
    next if files.empty?
    req('DELETE', "/edits/#{eid}/listings/#{lang}/#{type}")
    files.each do |f|
      code, r = upload_image(eid, lang, type, f)
      abort "#{lang} #{type} #{File.basename(f)} #{code} #{JSON.dump(r)}" unless code == 200
    end
    puts "#{lang}: #{files.length} #{type} uploaded"
  end
end

if DRY
  req('DELETE', "/edits/#{eid}"); puts 'DRY RUN: edit deleted'; exit 0
end
code, r = req('POST', "/edits/#{eid}:commit")
if code == 400 && JSON.dump(r).include?('changesNotSentForReview')
  code, r = req('POST', "/edits/#{eid}:commit?changesNotSentForReview=true")
end
abort "commit #{code} #{JSON.dump(r)}" unless code == 200
puts "COMMITTED #{eid}"

code, e2 = req('POST', '/edits'); e = e2['id']
code, l = req('GET', "/edits/#{e}/listings")
(l['listings'] || []).each do |x|
  counts = (SHOT_TYPES + GRAPHICS.keys).map do |t|
    c, im = req('GET', "/edits/#{e}/listings/#{x['language']}/#{t}")
    "#{t}=#{(im['images'] || []).length}"
  end
  puts "READ BACK #{x['language']}: title=#{x['title'].inspect} (#{x['title'].length}) " \
       "short=#{x['shortDescription'].length}c full=#{x['fullDescription'].length}c #{counts.join(' ')}"
end
req('DELETE', "/edits/#{e}")
