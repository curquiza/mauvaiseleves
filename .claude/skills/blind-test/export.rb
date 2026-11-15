#!/usr/bin/env ruby
# Exports chosen rows of the Google Sheet for a blind test: the decision texts (visible
# to the reviewing agent), the values filled by the script (hidden until the comparison),
# and the extraction rules, read from the collection code so they never drift.
#
#   cd collect
#   bundle exec ruby ../.claude/skills/blind-test/export.rb --rows 4-13 --out /tmp/blind
#   bundle exec ruby ../.claude/skills/blind-test/export.rb --rows 4,7,12 --out /tmp/blind

require "optparse"
require "json"
require "set"
require "fileutils"
collect = File.expand_path("../../../collect/lib", __dir__)
require_relative File.join(collect, "env")
require_relative File.join(collect, "sheets")
require_relative File.join(collect, "jev")
require_relative File.join(collect, "claude")

# Columns shown to the agent. Every other column written by the script is hidden;
# columns added by hand in the sheet (e.g. "verif agent 1") are not exported at all.
VISIBLE = %w[cid date_decision date_publication_jo nor lien_legifrance texte_complet].freeze
HIDDEN = %w[
  numero emetteur type type_probabilites nature_sanction nature_sanction_probabilites
  montant_euros entite_visee services emissions media media_probabilites motifs motifs_citations motifs_probabilites a_verifier
].freeze

options = {}
OptionParser.new do |opts|
  opts.on("--rows ROWS", "Sheet row numbers, e.g. 4-13 or 4,7,12 (required)") { |v| options[:rows] = v }
  opts.on("--out DIR", "Output directory, outside the repository (required)") { |v| options[:out] = v }
end.parse!
abort "Usage: export.rb --rows 4-13 --out DIR" unless options[:rows] && options[:out]

rows = options[:rows].split(",").flat_map do |part|
  first, last = part.split("-").map(&:to_i)
  (first..(last || first)).to_a
end.uniq.sort
abort "Rows must be below the header (row #{Sheets::HEADER_ROW})" if rows.any? { |r| r <= Sheets::HEADER_ROW }

Env.load
sheets = Sheets.new
header = sheets.header
values = sheets.send(:get_values, "#{Sheets::RANGE}!A1:ZZ#{rows.max}")

out = options[:out]
FileUtils.rm_rf(out)
FileUtils.mkdir_p(["#{out}/visible", "#{out}/hidden"])
hidden_lines = []

rows.each do |number|
  row = header.each_with_index.to_h { |column, i| [column, values.dig(number - 1, i).to_s] }
  abort "Row #{number} has no cid: it is not a decision written by the script" if row["cid"].empty?

  visible = VISIBLE.map { |c| c == "texte_complet" ? "\n#{row[c]}" : "#{c}: #{row[c]}" }.join("\n")
  File.write("#{out}/visible/ligne_#{number}.txt", visible)
  hidden_lines << "## ligne_#{number}.txt" << HIDDEN.map { |c| "- #{c}: #{row[c]}" } << ""
  puts "ligne #{number}: #{row['numero']} #{row['cid']}"
end
File.write("#{out}/hidden/valeurs_script.md", hidden_lines.flatten.join("\n"))

choices = Jev::CHOICES.map do |id, (question, options_map)|
  "- #{id} : « #{question} »\n" + options_map.map { |k, v| "  - #{k} : #{v}" }.join("\n")
end
File.write("#{out}/regles.md", <<~RULES)
  # Règles appliquées par le script

  ## Regex (règles implicites)
  - numero : numéro de la décision (ex. `2026-549`).
  - emetteur : `Arcom` ou `CSA` (l'ancien Conseil supérieur de l'audiovisuel).
  - montant_euros : montant de la sanction pécuniaire en euros (entier), vide sinon. Claude le fournit si la regex échoue.

  ## Claude (consigne verbatim)
  #{Claude::INSTRUCTIONS}
  ## Jev : questions à choix unique (un choix, avec une répartition de probabilités de somme 1)
  #{choices.join("\n")}

  nature_sanction n'est retenue que si type = sanction.

  ## Motifs : choisis par Claude (avec une citation), contrôlés par Jev
  Claude choisit les motifs dans la liste de sa consigne ci-dessus. Jev donne, pour chaque motif, une probabilité indépendante entre 0 et 1 (question : « Cette décision de l'autorité de régulation de l'audiovisuel (Arcom ou CSA) reproche-t-elle à l'éditeur le manquement suivant ? [description] »). Jev dit oui au-dessus de #{Jev::YES} et non en dessous de #{Jev::NO}. La colonne motifs contient les motifs de Claude ; motifs_probabilites, les probabilités de Jev.
RULES

puts "#{rows.size} rows exported to #{out}"
