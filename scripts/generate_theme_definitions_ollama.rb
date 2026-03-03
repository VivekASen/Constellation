#!/usr/bin/env ruby
# frozen_string_literal: true

$stdout.sync = true

require 'json'
require 'net/http'
require 'uri'

ROOT = File.expand_path('..', __dir__)
THEME_FILE = File.join(ROOT, 'Constellation', 'Resources', 'Themes', 'top_themes_library.txt')
OUT_FILE = File.join(ROOT, 'Constellation', 'Resources', 'Themes', 'theme_definitions_library.json')
MODEL = ENV.fetch('OLLAMA_MODEL', 'llama3.2:latest')
LIMIT = (ENV['LIMIT'] || '500').to_i
BATCH_SIZE = (ENV['BATCH_SIZE'] || '2').to_i
MAX_RETRIES = (ENV['MAX_RETRIES'] || '6').to_i
SLEEP_SEC = (ENV['SLEEP_SEC'] || '0.25').to_f

abort("Theme list not found: #{THEME_FILE}") unless File.exist?(THEME_FILE)

def normalize(theme)
  theme.downcase.strip.gsub('_', '-').gsub(' ', '-').gsub(/[^\p{Alnum}-]/, '').gsub(/-+/, '-').gsub(/^-|-$/, '')
end

def try_parse_json(str)
  JSON.parse(str)
rescue StandardError
  nil
end

def parse_map(raw)
  candidates = []
  candidates << raw.to_s

  text = raw.to_s
  start = text.index('{')
  finish = text.rindex('}')
  candidates << text[start..finish] if start && finish && finish > start

  candidates.each do |candidate|
    parsed = try_parse_json(candidate)
    return parsed if parsed.is_a?(Hash)
  end

  {}
end

def batch_prompt(batch)
  lines = batch.each_with_index.map { |t, i| "#{i + 1}. #{t}" }.join("\n")
  <<~PROMPT
    Generate unique, high-insight narrative theme definitions.

    Return STRICT JSON only as an object keyed by theme slug:
    {
      "theme-slug": {
        "summary": "2-3 sentences",
        "deepDive": "3-5 sentences",
        "connectionHint": "2-3 sentences on why works overlap under this theme",
        "watchFor": "1-2 concrete narrative signals"
      }
    }

    Rules:
    - no specific titles, franchises, creators, or character names
    - avoid repetitive phrasing and boilerplate
    - each theme must feel distinct and insightful
    - plain language, high signal

    Theme slugs:
    #{lines}
  PROMPT
end

def call_ollama(model, prompt)
  uri = URI('http://127.0.0.1:11434/api/generate')
  req = Net::HTTP::Post.new(uri)
  req['Content-Type'] = 'application/json'
  req.body = {
    model: model,
    prompt: prompt,
    stream: false,
    format: 'json',
    options: {
      temperature: 0.8,
      top_p: 0.95,
      num_predict: 1400
    }
  }.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 240
  http.open_timeout = 30
  res = http.request(req)
  [res.code.to_i, res.body]
end

all_themes = File.readlines(THEME_FILE, chomp: true)
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

missing = all_themes.reject { |t| existing.key?(t) }
puts "Model=#{MODEL} target=#{all_themes.size} existing=#{existing.size} missing=#{missing.size}"
exit 0 if missing.empty?

saved = 0
missing.each_slice([BATCH_SIZE, 1].max).with_index do |batch, idx|
  parsed = {}
  retries = 0

  while retries <= MAX_RETRIES
    code, body = call_ollama(MODEL, batch_prompt(batch))
    if code >= 200 && code <= 299
      outer = try_parse_json(body) || {}
      content = outer['response'].to_s
      parsed = parse_map(content)

      if parsed.is_a?(Hash) && !parsed.empty?
        break
      end
    end

    retries += 1
    sleep(0.7 + (retries * 0.5))
  end

  if parsed.empty?
    puts "Batch #{idx + 1}: failed after retries"
    next
  end

  accepted = 0
  batch.each do |theme|
    entry = parsed[theme] || parsed[theme.to_sym]

    # fallback: model returns just the definition object
    if entry.nil? && batch.size == 1 && parsed.key?('summary')
      entry = parsed
    end

    # fallback: model returns one arbitrary top-level key with the definition object
    if entry.nil? && batch.size == 1 && parsed.is_a?(Hash) && parsed.size == 1
      candidate = parsed.values.first
      if candidate.is_a?(Hash)
        entry = candidate
      end
    end

    next unless entry.is_a?(Hash)

    summary = entry['summary'].to_s.strip
    deep = entry['deepDive'].to_s.strip
    hint = entry['connectionHint'].to_s.strip
    watch = entry['watchFor'].to_s.strip
    next if [summary, deep, hint, watch].any?(&:empty?)

    existing[theme] = {
      'summary' => summary,
      'deepDive' => deep,
      'connectionHint' => hint,
      'watchFor' => watch
    }
    accepted += 1
    saved += 1
  end

  File.write(OUT_FILE, JSON.pretty_generate(existing))
  puts "Batch #{idx + 1}: accepted=#{accepted}/#{batch.size} saved_total=#{saved} file_total=#{existing.size}"
  sleep(SLEEP_SEC)
end

puts "Done. file_total=#{existing.size}"
