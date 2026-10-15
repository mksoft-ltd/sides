#!/usr/bin/env ruby
# Precheck-style validation of the local store text, run before any upload
# (fastlane's own precheck only reads what is already on App Store Connect).
# Checks store character limits, https URLs, banned audience wording
# (house-facts §31), leaked AI-conversation lines (§24) and placeholder text.
# Exit 1 on any failure.
ROOT = File.expand_path('../..', __dir__)
IOS = "#{ROOT}/ios/fastlane/metadata"
AND = "#{ROOT}/android/fastlane/metadata/android"
$fail = 0
def check(file, max, unit = :chars)
  unless File.exist?(file)
    puts "MISSING #{file.sub(ROOT + '/', '')}"; $fail += 1; return nil
  end
  t = File.read(file).strip
  n = unit == :bytes ? t.bytesize : t.length
  ok = n.positive? && n <= max
  puts format('%-4s %4d/%-4d %s', ok ? 'ok' : 'FAIL', n, max, file.sub(ROOT + '/', ''))
  $fail += 1 unless ok
  t
end
def scan(file, text)
  return unless text
  { /\b(for kids|toddlers?|for children)\b/i => 'kid-audience wording (§31)',
    /\b(as an ai|i'?ve (written|drafted)|here'?s (a|the|your) (draft|description)|let me know)\b/i => 'leaked AI-conversation line (§24)',
    /\b(TODO|TBD|lorem ipsum|XXX)\b/ => 'placeholder' }.each do |re, why|
    next unless text =~ re
    puts "FAIL #{why}: #{text[re].inspect} in #{file.sub(ROOT + '/', '')}"; $fail += 1
  end
end
%w[en-GB en-US].each do |l|
  d = "#{IOS}/#{l}"
  { 'name.txt' => 30, 'subtitle.txt' => 30, 'description.txt' => 4000, 'promotional_text.txt' => 170,
    'release_notes.txt' => 4000 }.each { |f, m| scan("#{d}/#{f}", check("#{d}/#{f}", m)) }
  check("#{d}/keywords.txt", 100, :bytes)
  %w[support_url marketing_url privacy_url].each do |u|
    t = check("#{d}/#{u}.txt", 255)
    next unless t
    unless t =~ %r{\Ahttps://\S+\z}
      puts "FAIL not an https URL: #{d}/#{u}.txt"; $fail += 1
    end
  end
end
check("#{IOS}/review_information/notes.txt", 4000)
ph = check("#{IOS}/review_information/phone_number.txt", 20)
(puts 'FAIL phone not +44 international'; $fail += 1) if ph && ph !~ /\A\+44\d{9,10}\z/
%w[copyright.txt primary_category.txt].each { |f| check("#{IOS}/#{f}", 200) }
Dir["#{AND}/*"].sort.each do |d|
  { 'title.txt' => 30, 'short_description.txt' => 80, 'full_description.txt' => 4000 }.each do |f, m|
    scan("#{d}/#{f}", check("#{d}/#{f}", m))
  end
  Dir["#{d}/changelogs/*.txt"].each { |f| check(f, 500) }
end
puts $fail.zero? ? 'metadata OK' : "#{$fail} problem(s)"
exit($fail.zero? ? 0 : 1)
