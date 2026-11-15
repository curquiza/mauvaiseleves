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
  montant entite_visee services emissions resume media media_probabilites motifs motifs_probabilites a_verifier
].freeze

options = {}
OptionParser.new do |opts|
  opts.on("--rows ROWS", "Sheet row numbers, e.g. 4-13 or 4,7,12 (required)") { |v| options[:rows] = v }
  opts.on("--out DIR", "Output directory, outside the repository (required)") { |v| options[:out] = v }
  opts.on("--tab NAME", "Sheet tab to read (default: v1)") { |v| options[:tab] = v }
end.parse!
abort "Usage: export.rb --rows 4-13 --out DIR" unless options[:rows] && options[:out]

rows = options[:rows].split(",").flat_map do |part|
  first, last = part.split("-").map(&:to_i)
  (first..(last || first)).to_a
end.uniq.sort
abort "Rows must be below the header (row #{Sheets::HEADER_ROW})" if rows.any? { |r| r <= Sheets::HEADER_ROW }

Env.load
sheets = Sheets.new(options[:tab] || Sheets::DEFAULT_TAB)
header = sheets.header
values = sheets.send(:get_values, "#{sheets.range}!A1:ZZ#{rows.max}")

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
  - montant : montant de la sanction pécuniaire avec sa devise, tel qu'écrit dans la décision (« 200 000 € », ou « 200 000 F » pour les francs, jamais converti), vide sinon. Claude le fournit si la regex échoue.

  ## Normalisations faites par le code après Claude
  - montant : toujours écrit « 25 000 € », ou « 25 000 F » pour les francs, quel que soit le mot du texte (« euros », « francs »).
  - entite_visee : « Limited », « Ltd » et « GmbH » en fin de nom sont retirés, comme SA, SAS, SARL, SAM (société anonyme monégasque) ou SCOP.
  - services : une fréquence écrite après le nom du service est retirée (« Tonic FM 91,1 MHz » devient « Tonic FM »).
  - entite_visee et services : les anciennes graphies de TF1 (« T.F.1 », « T.F. 1 », « TF 1 », « Télévision française 1 ») sont écrites « TF1 ».
  - nature_sanction : vide quand le dispositif est absent de Légifrance (on ne peut pas la connaître).
  - type : l'abrogation d'une autorisation après que l'éditeur y a renoncé est une clôture sans sanction, pas une sanction.
  - entite_visee : le code retire le sigle final entre parenthèses (« Société d'exploitation d'un service d'information (SESI) » devient « Société d'exploitation d'un service d'information »), la forme juridique en tête ou en fin de nom (« SAS Voltage » devient « Voltage », « Traffic Ready SA » devient « Traffic Ready »), et met la première lettre en majuscule (« Ministère de l'action… »). Compare l'entité après ces normalisations.
  - type « clôture sans sanction » : la liste de motifs est vide par convention, et le script ne signale aucun écart de motif pour ces lignes.
  - Les valeurs de Jev entre 0,3 et 0,7 ne sont pas signalées dans a_verifier, par choix : seuls les désaccords nets (Jev au-dessus de 0,7 sur un motif absent chez Claude, ou sous 0,3 sur un motif retenu par Claude) le sont.
  - resume : la limite de 25 mots est indicative ; un dépassement de quelques mots est accepté et n'est pas une erreur.

  ## Conventions déjà appliquées par le script (ce ne sont pas des erreurs)
  - services : quand une émission est diffusée sur deux services (par exemple France Inter et Franceinfo), on retient seulement le service que vise le dispositif de la décision.
  - emissions : dans une décision qui sanctionne d'autres émissions, une émission examinée mais pour laquelle la décision dit qu'il n'y a pas lieu de sanctionner est exclue ; pour une clôture sans sanction, l'émission poursuivie est gardée ; une émission de correction qui est elle-même reprochée est incluse ; pour une décision sur une période (pluralisme sur un mois), on liste les émissions citées en exemple, pas l'échantillon visionné.

  ## Claude (consigne verbatim)
  #{Claude::INSTRUCTIONS}
  ## Jev : questions à choix unique (un choix, avec une répartition de probabilités de somme 1)
  #{choices.join("\n")}

  nature_sanction n'est retenue que si type = sanction.

  ## Motifs : choisis par Claude, contrôlés par Jev
  Claude choisit les motifs dans la liste de sa consigne ci-dessus. Jev reçoit, pour chaque motif, la même question et les mêmes critères « Oui » et « Non », et donne une probabilité indépendante entre 0 et 1. Jev dit oui au-dessus de #{Jev::YES} et non en dessous de #{Jev::NO}. La colonne motifs contient les motifs de Claude ; motifs_probabilites, les probabilités de Jev. Jev lit la décision découpée en trois parties : titre, considerants et dispositif.
RULES

puts "#{rows.size} rows exported to #{out}"
