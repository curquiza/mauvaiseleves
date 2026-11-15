# Grounds (motifs) a decision can reproach, shared by Claude and Jev so that both
# judge against the same definitions. Descriptions are in French, like the decisions.
module Motifs
  DEFINITIONS = {
    "haine_discrimination" => "Les propos diffusés incitent à la haine ou à la violence, ou encouragent des comportements discriminatoires (origine, religion, nationalité, sexe, orientation sexuelle, handicap…).",
    "maitrise_antenne" => "La décision reproche à l'éditeur de ne pas avoir conservé la maîtrise de son antenne pendant l'émission : propos non recadrés en direct, débat non maîtrisé, ou propos tenus par l'animateur lui-même sans réaction. Un choix éditorial ou de programmation déséquilibré relève de honnetete_information ou de pluralisme, pas de ce motif.",
    "honnetete_information" => "La décision reproche explicitement un manquement à l'honnêteté, la rigueur, la mesure ou l'indépendance de l'information : fait présenté comme certain sans vérification, montage trompeur, défaut de contradiction sur un sujet d'actualité, choix éditorial déséquilibré, ou comptes rendus sans mesure ni honnêteté, y compris de l'actualité électorale (ce cas relève de ce motif seul, pas de pluralisme). La simple présence d'une affirmation non sourcée dans les propos cités ne suffit pas.",
    "pluralisme" => "Manquement au pluralisme politique ou des courants de pensée : équité des temps de parole (y compris en période électorale) ou déséquilibre dans l'expression des courants de pensée et d'opinion. Le manque de mesure ou d'honnêteté dans les comptes rendus de l'actualité, même électorale, relève de honnetete_information, pas de ce motif.",
    "droits_personne" => "La décision reproche une atteinte à la dignité humaine, à la vie privée, à la présomption d'innocence ou aux droits d'une personne. La stigmatisation d'un groupe relève de haine_discrimination, pas de ce motif.",
    "protection_mineurs" => "Manquement à la protection du jeune public dans les programmes de radio ou de télévision : signalétique, classification ou horaire de diffusion inadapté. L'absence de vérification de l'âge sur un site pornographique relève de verification_age, pas de ce motif.",
    "publicite" => "Manquement aux règles de la publicité, du parrainage, du placement de produit ou du téléachat.",
    "quotas_chansons" => "Non-respect des quotas de chansons d'expression française ou des engagements de programmation musicale (nouveaux talents, nouvelles productions, diversité des titres diffusés).",
    "conditions_techniques" => "Non-respect des conditions techniques d'émission : fréquence, puissance, site d'émission, déviation de fréquence, ou absence d'émission.",
    "programme_autorisation" => "Le programme diffusé ne correspond pas au format général prévu par l'autorisation (catégorie de radio, part de programmes locaux, thématique de la chaîne). Les engagements de programmation musicale relèvent de quotas_chansons, et le contenu des propos tenus à l'antenne n'est pas concerné.",
    "obligations_declaratives" => "Défaut de transmission de documents à l'autorité (comptes, enregistrements, déclarations, informations demandées).",
    "creation_production" => "Non-respect des quotas de diffusion ou des obligations de financement d'œuvres audiovisuelles ou cinématographiques (films, séries, documentaires) par une chaîne de télévision ou un service de vidéo à la demande. Jamais les chansons ni les radios : les quotas de chansons relèvent de quotas_chansons.",
    "verification_age" => "Absence de vérification de l'âge sur un service en ligne à caractère pornographique.",
    "medias_sous_sanctions" => "Diffusion de médias visés par des sanctions de l'Union européenne (médias russes notamment).",
    "accessibilite" => "Non-respect des obligations d'accessibilité aux personnes handicapées : accessibilité numérique d'un site ou service en ligne (RGAA, déclaration d'accessibilité, loi du 11 février 2005), accessibilité des programmes (sous-titrage, audiodescription), ou dépôt par un éditeur des fichiers numériques de ses œuvres pour faciliter leur accès aux personnes handicapées (exception handicap au droit d'auteur, dépôt à la BnF)."
  }.freeze

  # Media types a ground can apply to. Grounds not listed apply to any media type.
  APPLICABLE_MEDIA = {
    "creation_production" => %w[television video_a_la_demande],
    "quotas_chansons" => %w[radio],
    "verification_age" => %w[en_ligne]
  }.freeze

  def self.applies?(motif, media)
    APPLICABLE_MEDIA.fetch(motif, [media]).include?(media)
  end

  # "- haine_discrimination : Les propos diffusés…", one line per ground.
  def self.list
    DEFINITIONS.map { |id, description| "- #{id} : #{description}" }.join("\n")
  end
end
