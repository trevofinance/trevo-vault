#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

MINIMUM_PLAY_SCORE = 25.0
R8_METADATA_PATH = "BUNDLE-METADATA/com.android.tools/r8.json"

def abort_check(message)
  warn "ERROR: #{message}"
  exit 1
end

if ARGV.length != 1
  warn "Usage: #{$PROGRAM_NAME} path/to/app.aab"
  exit 2
end

aab = ARGV.first
abort_check("AAB not found: #{aab}") unless File.file?(aab)

r8_json, r8_error, r8_status = Open3.capture3("unzip", "-p", aab, R8_METADATA_PATH)
unless r8_status.success? && !r8_json.empty?
  abort_check("#{R8_METADATA_PATH} is missing. The release was built without R8 optimization. #{r8_error.strip}")
end

metadata = JSON.parse(r8_json)
options = metadata.fetch("options")
required_options = {
  "isObfuscationEnabled" => "obfuscation",
  "isOptimizationsEnabled" => "optimization",
  "isShrinkingEnabled" => "shrinking"
}
required_options.each do |key, label|
  abort_check("R8 #{label} is disabled in #{R8_METADATA_PATH}") unless options[key] == true
end

stats = metadata.fetch("stats")
scores = {
  "obfuscation" => 100.0 - Float(stats.fetch("noObfuscationPercentage")),
  "optimization" => 100.0 - Float(stats.fetch("noOptimizationPercentage")),
  "shrinking" => 100.0 - Float(stats.fetch("noShrinkingPercentage"))
}

scores.each do |label, score|
  unless score.between?(MINIMUM_PLAY_SCORE, 100.0)
    abort_check("DEX #{label} score is #{format('%.2f', score)}%; Google Play requires at least #{MINIMUM_PLAY_SCORE.to_i}%")
  end
end

listing, listing_error, listing_status = Open3.capture3("unzip", "-l", aab)
abort_check("Could not list AAB contents: #{listing_error.strip}") unless listing_status.success?
dex_bytes = listing.each_line.sum do |line|
  fields = line.split
  fields.length >= 4 && fields.last.end_with?(".dex") ? fields.first.to_i : 0
end
abort_check("No DEX files found in the bundle") if dex_bytes.zero?

score_summary = scores.map { |label, score| "#{label}=#{format('%.2f', score)}%" }.join(", ")
puts "DEX optimization verified: #{score_summary}; DEX size=#{format('%.2f', dex_bytes / 1024.0 / 1024.0)} MiB"
