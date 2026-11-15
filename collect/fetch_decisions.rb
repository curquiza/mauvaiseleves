#!/usr/bin/env ruby
# Fetches the sanctions and formal notices (mises en demeure) of Arcom (and the former
# CSA) published in the Journal officiel, through the Légifrance API, and appends the
# ones not yet in the Google Sheet.
#
#   bundle exec ruby fetch_decisions.rb --dry-run
#   bundle exec ruby fetch_decisions.rb --limit 10

require "date"
require "optparse"
require "set"
require_relative "lib/env"
require_relative "lib/legifrance"
require_relative "lib/extract"
require_relative "lib/jev"
require_relative "lib/claude"
require_relative "lib/sheets"

Env.load

options = { since: nil, limit: nil, dry_run: false, cost: false }
OptionParser.new do |opts|
  opts.on("--since DATE", "Only texts published on or after this date, YYYY-MM-DD (default: all dates)") { |v| options[:since] = Date.iso8601(v) }
  opts.on("--limit N", Integer, "Only the N most recent new texts, for testing (default: all)") { |v| options[:limit] = v }
  opts.on("--dry-run", "List the new decisions without calling Claude or Jev nor writing to the sheet") { options[:dry_run] = true }
  opts.on("--cost", "Show the tokens used and the cost of Claude and Jev at the end") { options[:cost] = true }
end.parse!

# Expressions searched in titles. They cover "portant sanction", "prononçant une sanction",
# "relative à la procédure de sanction", "à titre de sanction", "mettant en demeure",
# "portant mise en demeure", etc.
SEARCHES = ["sanction", "en demeure"].freeze

COLUMNS = %w[
  cid date_ajout date_decision date_publication_jo numero emetteur type type_probabilites
  nature_sanction nature_sanction_probabilites
  montant_euros entite_visee titre nor lien_legifrance texte_complet
  services emissions media media_probabilites motifs motifs_citations motifs_probabilites a_verifier
].freeze

BATCH_SIZE = 10 # rows written to the sheet at once, so a crash loses little paid work
CELL_LIMIT = 50_000 # maximum number of characters in a Google Sheets cell

# "radio: 0.97 ; television: 0.02 ; ..."
def format_probabilities(probabilities)
  probabilities.map { |option, p| "#{option}: #{p.to_f.round(2)}" }.join(" ; ")
end

# Grounds come from Claude (with a quote). Jev judges each ground independently:
# disagreements go to a_verifier. Grounds that cannot apply to the media type are
# ignored on Jev's side and flagged on Claude's side.
def motif_checks(claude_motifs, probabilities, media)
  checks = []
  claude_motifs.each do |motif|
    p = probabilities[motif].to_f
    checks << "motif inhabituel pour ce média : #{motif}" unless Motifs.applies?(motif, media)
    checks << "motif contesté par Jev : #{motif} (#{p.round(2)})" if p < Jev::NO
  end
  probabilities.each do |motif, p|
    next if claude_motifs.include?(motif) || p.to_f < Jev::YES || !Motifs.applies?(motif, media)

    checks << "motif vu par Jev seul : #{motif} (#{p.to_f.round(2)})"
  end
  checks
end

def format_cost(dollars)
  dollars.nil? ? "prix inconnu" : format("%.4f $", dollars)
end

def print_cost(claude, jev, processed)
  usage = claude.usage
  warn "Claude (#{Claude::MODEL}): #{claude.calls} calls, #{usage[:input]} input tokens, " \
       "#{usage[:cache_read]} read from cache, #{usage[:cache_write]} written to cache, " \
       "#{usage[:output]} output tokens: #{format_cost(claude.cost)}"
  warn "Jev (#{Jev::MODEL}): #{jev.calls} calls, #{jev.input_tokens} input tokens: #{format_cost(jev.cost)}"
  return if claude.cost.nil? || processed.zero?

  total = claude.cost + jev.cost
  warn "Total: #{format_cost(total)}, i.e. #{format_cost(total / processed)} per decision"
end

sheets = Sheets.new
sheets.check_columns!(COLUMNS)
known = sheets.existing_cids
warn "#{known.size} decisions already in the sheet"

legifrance = Legifrance.new
warn "Searching decisions on the Légifrance API…"
results = SEARCHES.flat_map { |expression| legifrance.search_titles(expression) }
results = results.uniq { |r| r.dig("titles", 0, "cid") }
results = results.select { |r| r["nature"].to_s =~ /d[ée]cision/i }
results = results.reject { |r| known.include?(r.dig("titles", 0, "cid")) }
results = results.select { |r| r["datePublication"].to_s[0, 10] >= options[:since].iso8601 } if options[:since]
results = results.sort_by { |r| r["datePublication"].to_s }.reverse
results = results.first(options[:limit]) if options[:limit]
warn "#{results.size} new decisions to process"

if options[:dry_run]
  results.each { |r| warn "  #{r['datePublication'].to_s[0, 10]} #{Extract.title(r.dig('titles', 0, 'title'))[0, 110]}" }
  exit
end

jev = Jev.new
claude = Claude.new
batch = []
written = 0

begin
  results.each_with_index do |result, index|
    cid = result.dig("titles", 0, "cid")
    decision = legifrance.decision(cid)
    title = Extract.title(decision["title"])
    dispositif = Extract.dispositif(decision)
    regex_type = Extract.measure_type(title, dispositif)
    next if regex_type.nil?

    warn "[#{index + 1}/#{results.size}] #{title[0, 100]}"
    full_text = Extract.full_text(decision)

    extraction = claude.extract(cid, full_text)
    classification = jev.classify(full_text)
    probabilities = classification["motifs"]
    media = classification["media"]
    # Type and kind of sanction come from Jev; the regex answers are only used to cross-check.
    type = classification["type"]["choice"]
    kind = classification["nature"]["choice"] if type == "sanction"
    regex_kind = Extract.sanction_kind(dispositif, title) if regex_type == "sanction"
    entity = extraction["entite_visee"].to_s.strip
    claude_motifs = extraction["motifs"].uniq { |m| m["motif"] }
    motifs = claude_motifs.map { |m| m["motif"] }
    regex_amount = Extract.amount(dispositif)
    amount = regex_amount || extraction["montant_euros"]

    checks = []
    checks << "texte tronqué dans le Sheet" if full_text.size > CELL_LIMIT
    checks << "type : regex = #{regex_type}, Jev = #{type}" if regex_type != "à vérifier" && regex_type != type
    checks << "type incertain" if classification["type"]["confidence"].to_f < Jev::MIN_CONFIDENCE
    if type == "sanction"
      checks << "nature : regex = #{regex_kind}, Jev = #{kind}" if regex_kind && regex_kind != kind
      checks << "nature de sanction incertaine" if classification["nature"]["confidence"].to_f < Jev::MIN_CONFIDENCE
    end
    checks << "entité visée non trouvée" if entity.empty?
    checks << "forme de l'entité visée à vérifier" if !entity.empty? && !entity.match?(/\A(\p{Lu}|\d|\[)/)
    checks << "montant trouvé par Claude" if regex_amount.nil? && amount
    checks << "montant non trouvé" if kind == "amende" && amount.nil?
    checks << "montant absent du texte" if amount && !Extract.amount_in_text?(amount, full_text)
    checks << "montant alors que le type est #{type}" if amount && type != "sanction"
    checks << "service non trouvé" if extraction["services"].empty? && !%w[edition autre].include?(media["choice"])
    checks << "doute Claude : #{extraction['doute']}" unless extraction["doute"].to_s.strip.empty?
    checks << "aucun motif" if motifs.empty?
    checks.concat(motif_checks(motifs, probabilities, media["choice"]))
    checks << "type de média incertain" if media["confidence"].to_f < Jev::MIN_CONFIDENCE

    batch << {
      "cid" => cid,
      "date_ajout" => Date.today.iso8601,
      "date_decision" => Extract.date(decision["dateTexte"]),
      "date_publication_jo" => Extract.date(decision["dateParution"]),
      "numero" => Extract.number(title),
      "emetteur" => Extract.emitter(decision["nor"]),
      "type" => type,
      "type_probabilites" => format_probabilities(classification["type"]["probabilities"]),
      "nature_sanction" => kind,
      "nature_sanction_probabilites" => (format_probabilities(classification["nature"]["probabilities"]) if kind),
      "montant_euros" => amount,
      "entite_visee" => entity,
      "titre" => title,
      "nor" => decision["nor"],
      "lien_legifrance" => "https://www.legifrance.gouv.fr/jorf/id/#{cid}",
      "texte_complet" => full_text[0, CELL_LIMIT],
      "services" => extraction["services"].join(" ; "),
      "emissions" => extraction["emissions"].map { |e| "#{e['titre']} (#{e['dates_diffusion'].join(', ')})" }.join(" ; "),
      "media" => media["choice"],
      "media_probabilites" => format_probabilities(media["probabilities"]),
      "motifs" => motifs.join(" ; "),
      "motifs_citations" => claude_motifs.map { |m| "#{m['motif']} : « #{m['citation']} »" }.join(" ; "),
      "motifs_probabilites" => format_probabilities(probabilities),
      "a_verifier" => checks.join(" ; ")
    }

    next if batch.size < BATCH_SIZE

    sheets.append(batch)
    written += batch.size
    batch = []
  end
ensure
  # Also on errors, so that rows already paid for are not lost.
  sheets.append(batch)
  written += batch.size
  warn "#{written} rows added to the sheet"
  print_cost(claude, jev, claude.calls) if options[:cost]
end
