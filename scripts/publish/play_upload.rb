#!/usr/bin/env ruby
# Upload build/app/outputs/bundle/release/app-release.aab to a Play track with
# the raw androidpublisher API (supply's uploader stalls: house-facts §28).
#   --track=internal (default)   --status=completed (default; IAP creation needs
#   an ACTIVE billing artifact, a draft does not count)   --dry-run
# Refuses an AAB not signed by the upload key, and writes release notes only for
# the locales the live listing has (house-facts §19).
require_relative 'play'
require 'open3'

ROOT = File.expand_path('../..', __dir__)
AAB = "#{ROOT}/build/app/outputs/bundle/release/app-release.aab"
UPLOAD_SHA1 = 'EA:80:6D:C6:0D:14:F6:34:88:3C:00:01:8D:99:A0:D9:D4:EA:B6:95'
DRY = ARGV.include?('--dry-run')
arg = ->(k, d) { (ARGV.find { |a| a.start_with?("--#{k}=") } || "--#{k}=#{d}").split('=', 2).last }
TRACK = arg.('track', 'internal'); STATUS = arg.('status', 'completed')
VERSION_NAME = File.read("#{ROOT}/pubspec.yaml")[/^version:\s*([^\s+]+)/, 1] or abort 'no version in pubspec'

abort "no AAB at #{AAB}" unless File.exist?(AAB)
out, = Open3.capture2e('keytool', '-printcert', '-jarfile', AAB)
abort "AAB is not signed by the upload key:\n#{out}" unless out.include?("SHA1: #{UPLOAD_SHA1}")
puts "AAB signer = upload key #{UPLOAD_SHA1}"

code, edit = req('POST', '/edits'); abort "edit #{code} #{edit}" unless code == 200
eid = edit['id']
size = File.size(AAB)
uri = URI("https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/#{PKG}/edits/#{eid}/bundles?uploadType=media")
r = Net::HTTP::Post.new(uri)
r['Authorization'] = "Bearer #{TOK}"; r['Content-Type'] = 'application/octet-stream'; r['Content-Length'] = size.to_s
r.body_stream = File.open(AAB, 'rb')
t0 = Time.now
res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 1800, write_timeout: 1800) { |h| h.request(r) }
body = JSON.parse(res.body) rescue res.body
abort "bundle upload #{res.code} #{body}" unless res.code.to_i == 200
vc = body['versionCode']
puts "uploaded versionCode=#{vc} (#{(size / 1048576.0).round(1)}MB) in #{(Time.now - t0).round}s"

code, l = req('GET', "/edits/#{eid}/listings")
langs = (l['listings'] || []).map { |x| x['language'] }
notes = langs.filter_map do |lang|
  f = "#{ROOT}/android/fastlane/metadata/android/#{lang}/changelogs/#{vc}.txt"
  { language: lang, text: File.read(f).strip } if File.exist?(f)
end
track = { track: TRACK, releases: [{ name: "#{VERSION_NAME} (#{vc})", versionCodes: [vc.to_s],
                                     status: STATUS, releaseNotes: notes }] }
code, d = req('PUT', "/edits/#{eid}/tracks/#{TRACK}", track)
abort "track #{code} #{JSON.dump(d)}" unless code == 200
puts "#{TRACK}: #{STATUS} #{VERSION_NAME} (#{vc}), notes for #{notes.map { |n| n[:language] }.inspect}"
if DRY
  req('DELETE', "/edits/#{eid}"); puts 'DRY RUN: edit deleted'; exit 0
end
code, d = req('POST', "/edits/#{eid}:commit")
abort "commit #{code} #{JSON.dump(d)} (re-read with a fresh edit before retrying: it may have committed)" unless code == 200
puts "COMMITTED #{eid}"
code, e2 = req('POST', '/edits')
code, t = req('GET', "/edits/#{e2['id']}/tracks/#{TRACK}")
puts "READ BACK #{TRACK}: #{JSON.dump(t['releases'])}"
req('DELETE', "/edits/#{e2['id']}")
