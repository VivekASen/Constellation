#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

ROOT = File.expand_path('..', __dir__)
THEME_FILE = File.join(ROOT, 'Constellation', 'Resources', 'Themes', 'top_themes_library.txt')
OUT_FILE = File.join(ROOT, 'Constellation', 'Resources', 'Themes', 'theme_definitions_library.json')
MODEL = ENV.fetch('GEMINI_MODEL', 'gemini-2.5-flash')
BATCH_SIZE = (ENV['BATCH_SIZE'] || '4').to_i
LIMIT = (ENV['LIMIT'] || '500').to_i
SLEEP_SEC = (ENV['SLEEP_SEC'] || '1.5').to_f
MAX_RETRIES = (ENV['MAX_RETRIES'] || '8').to_i

api_key = ENV.fetch('GEMINI_API_KEY', '').strip
abort('Missing GEMINI_API_KEY') if api_key.empty?
abort("Theme list not found: #{THEME_FILE}") unless File.exist?(THEME_FILE)

def normalize(theme)
  theme.downcase.strip.gsub('_', '-').gsub(' ', '-').gsub(/[^\p{Alnum}-]/, '').gsub(/-+/, '-').gsub(/^-|-$/, '')
end

def endpoint(model)
  URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent")
end

def extract_text(response_json)
  candidates = response_json.fetch('candidates', [])
  parts = candidates.flat_map { |c| c.dig('content', 'parts') || [] }
  text = parts.map { |p| p['text'] }.compact.join("\n").strip
  text.gsub(/\A```(?:json)?\s*/m, '').gsub(/\s*```\z/m, '')
end

def parse_map(raw)
  data = JSON.parse(raw)
  return data if data.is_a?(Hash)
  {}
rescue JSON::ParserError
  start = raw.index('{')
  ending = raw.rindex('}')
  return {} unless start && ending && ending > start
  JSON.parse(raw[start..ending])
rescue StandardError
  {}
end

def batch_prompt(batch)
  numbered = batch.each_with_index.map { |t, i| "#{i + 1}. #{t}" }.join("\n")
  <<~PROMPT
    You are writing a permanent offline theme-definition library for a media analysis app.

    Produce deeply insightful, varied, non-repetitive entries for each theme below.

    Requirements for EACH theme entry:
    - unique voice and sentence rhythm relative to other entries in this response
    - specific narrative insight, not dictionary definitions
    - no references to any specific title, franchise, creator, or character names
    - avoid boilerplate and repeated sentence openings
    - plain language, but intellectually strong

    Return STRICT JSON only in this shape:
    {
      "theme-slug": {
        "summary": "2-3 sentences",
        "deepDive": "3-5 sentences",
        "connectionHint": "2-3 sentences on why different works overlap under this theme",
        "watchFor": "1-2 sentences of concrete narrative signals"
      }
    }

    Theme slugs:
    #{numbered}
  PROMPT
end

def call_gemini(uri, api_key, prompt)
  req = Net::HTTP::Post.new(uri)
  req['Content-Type'] = 'application/json'
  req['x-goog-api-key'] = api_key
  req.body = {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: 0.8,
      responseMimeType: 'application/json'
    }
  }.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 120
  http.open_timeout = 30
  res = http.request(req)
  [res.code.to_i, res.body]
end

def retry_delay_seconds(error_body)
  msg = begin
    parsed = JSON.parse(error_body)
    parsed.dig('error', 'message').to_s
  rescue StandardError
    error_body.to_s
  end

  if (m = msg.match(/Please retry in\s+([0-9.]+)s\b/i))
    return m[1].to_f + 0.6
  end
  if (m = msg.match(/Please retry in\s+([0-9.]+)ms\b/i))
    return (m[1].to_f / 1000.0) + 0.6
  end
  8.0
end

themes = File.readlines(THEME_FILE, chomp: true)
             .map(&:strip)
             .reject { |t| t.empty? || t.start_with?('#') }
             .map { |t| normalize(t) }
             .uniq
             .first([LIMIT, 1].max)

existing = if File.exist?(OUT_FILE)
  begin
    JSON.parse(File.read(OUT_FILE))
  rescue StandardError
    {}
  end
else
  {}
end

missing = themes.reject { |t| existing.key?(t) }
puts "Themes target: #{themes.size}, existing: #{existing.size}, missing: #{missing.size}"
exit 0 if missing.empty?

uri = endpoint(MODEL)
processed = 0

missing.each_slice([BATCH_SIZE, 1].max).with_index do |batch, idx|
  retries = 0
  saved_this_batch = false

  until saved_this_batch || retries > MAX_RETRIES
    code, body = call_gemini(uri, api_key, batch_prompt(batch))

    if code >= 200 && code <= 299
      parsed = begin
        json = JSON.parse(body)
        parse_map(extract_text(json))
      rescue StandardError
        {}
      end

      if parsed.empty?
        retries += 1
        sleep(3.0)
        next
      end

      batch.each do |theme|
        entry = parsed[theme] || parsed[theme.to_sym]
        next unless entry.is_a?(Hash)
        summary = entry['summary'].to_s.strip
        deep = entry['deepDive'].to_s.strip
        hint = entry['connectionHint'].to_s.strip
        watch = entry['watchFor'].to_s.strip
        next if summary.empty? || deep.empty? || hint.empty? || watch.empty?

        existing[theme] = {
          'summary' => summary,
          'deepDive' => deep,
          'connectionHint' => hint,
          'watchFor' => watch
        }
        processed += 1
      end

      File.write(OUT_FILE, JSON.pretty_generate(existing))
      puts "Batch #{idx + 1}: saved cumulative=#{processed}, file_total=#{existing.size}"
      saved_this_batch = true
      sleep(SLEEP_SEC)
    elsif code == 429
      retries += 1
      delay = retry_delay_seconds(body)
      puts "Batch #{idx + 1}: 429 retry #{retries}/#{MAX_RETRIES}, sleeping #{format('%.1f', delay)}s"
      sleep(delay)
    else
      retries += 1
      puts "Batch #{idx + 1}: HTTP #{code}, retry #{retries}/#{MAX_RETRIES}"
      sleep(6.0)
    end
  end

  unless saved_this_batch
    puts "Batch #{idx + 1}: skipped after retries"
  end
end

puts "Done. Wrote #{existing.size} entries to #{OUT_FILE}"
