# Grounds (motifs) a decision can reproach, shared by Claude and Jev so that both
# judge against the same definitions. Texts are in French, like the decisions.
#
# Following TypeSafe's guidance, each ground is one short question, plus what a "yes"
# and a "no" mean. The "no" describes, as a concrete situation, the case most often
# confused with this ground.
module Motifs
  DEFINITIONS = {
    "haine_discrimination" => {
      question: "La décision reproche-t-elle des propos qui incitent à la haine ou encouragent des comportements discriminatoires ?",
      oui: "La décision retient des propos qui stigmatisent un groupe en raison de son origine, sa religion, sa nationalité, son sexe, son orientation sexuelle ou son handicap.",
      non: "La décision reproche seulement un déséquilibre politique, une erreur factuelle ou un défaut technique, sans propos visant un groupe."
    },
    "maitrise_antenne" => {
      question: "La décision reproche-t-elle à l'éditeur de ne pas avoir conservé la maîtrise de son antenne ?",
      oui: "Des propos tenus pendant l'émission n'ont été ni recadrés ni contredits, ou l'animateur les a tenus lui-même sans réaction.",
      non: "La décision critique un choix éditorial ou la programmation sur une période, ou reproche au journaliste une erreur factuelle seulement comme un manque de rigueur, sans grief de maîtrise de l'antenne."
    },
    "honnetete_information" => {
      question: "La décision reproche-t-elle un manquement à l'honnêteté, à la rigueur ou à la mesure de l'information ?",
      oui: "La décision reproche un fait présenté sans vérification, un montage trompeur, un défaut de contradiction, des commentaires sans mesure (y compris sur l'actualité électorale) ou le traitement univoque d'une procédure judiciaire en cours.",
      non: "Un invité avance une affirmation non sourcée, mais la décision ne reproche à l'éditeur que des propos discriminatoires ou un déséquilibre des temps de parole."
    },
    "pluralisme" => {
      question: "La décision reproche-t-elle un manquement au pluralisme des courants de pensée et d'opinion ?",
      oui: "La décision constate un déséquilibre des temps de parole ou de l'expression des courants politiques ou de pensée.",
      non: "La décision reproche seulement un manque de mesure ou d'honnêteté dans les commentaires, même en période électorale, ou de ne pas avoir présenté les différentes thèses dans le traitement d'une procédure judiciaire en cours."
    },
    "droits_personne" => {
      question: "La décision reproche-t-elle une atteinte aux droits d'une personne précise ?",
      oui: "Atteinte à la dignité, à la vie privée ou à la présomption d'innocence d'une personne identifiable.",
      non: "Les propos visent un groupe entier, sans personne précise mise en cause ; ou des affirmations fausses sur une personne sont relevées, mais la décision les reproche comme un manque de rigueur de l'information, pas comme une atteinte à ses droits."
    },
    "protection_mineurs" => {
      question: "La décision reproche-t-elle un manquement à la protection du jeune public ?",
      oui: "Signalétique, classification ou horaire de diffusion inadapté au jeune public, communication commerciale interdite dans ou autour des programmes pour enfants (par exemple pour des jeux d'argent), ou site pornographique accessible sans système de vérification de l'âge conforme.",
      non: "La décision reproche une publicité ou des propos sans rapport avec l'exposition du jeune public, par exemple une publicité clandestine dans une émission pour adultes."
    },
    "publicite" => {
      question: "La décision reproche-t-elle un manquement aux règles de la publicité ?",
      oui: "Publicité, parrainage, placement de produit ou téléachat non conforme aux règles.",
      non: "La décision ne mentionne la publicité qu'à propos des ressources ou du modèle économique de l'éditeur."
    },
    "quotas_culturels" => {
      question: "La décision reproche-t-elle le non-respect de quotas ou d'obligations en faveur des chansons ou des œuvres audiovisuelles et cinématographiques ?",
      oui: "Une radio n'a pas diffusé assez de chansons d'expression française, de nouveaux talents ou de nouvelles productions, ou une chaîne de télévision ou un service de vidéo à la demande n'a pas assez diffusé ou financé de films, séries ou documentaires.",
      non: "La radio n'émet plus du tout, ou n'a pas transmis ses enregistrements."
    },
    "non_respect_autorisation" => {
      question: "La décision reproche-t-elle de ne pas respecter les conditions de l'autorisation d'émettre ?",
      oui: "Aucun programme n'est diffusé sur la fréquence autorisée, l'émission se fait depuis un autre site ou avec une puissance ou une déviation de fréquence non conforme, ou le programme ne correspond pas au format prévu (catégorie de radio, part de programmes locaux, thématique de la chaîne).",
      non: "La décision reproche seulement des quotas de chansons, des propos tenus à l'antenne ou des documents non transmis."
    },
    "obligations_declaratives" => {
      question: "La décision reproche-t-elle de ne pas avoir transmis des documents ou des informations à l'Arcom ?",
      oui: "Comptes, enregistrements, déclarations ou informations demandés par l'Arcom n'ont pas été fournis.",
      non: "Le document manquant devait être remis à un autre organisme que l'Arcom, par exemple la BnF, ou l'éditeur n'a simplement pas présenté d'observations pendant la procédure."
    },
    "medias_interdits_ue" => {
      question: "La décision reproche-t-elle la diffusion d'un média visé par des sanctions de l'Union européenne ?",
      oui: "Diffusion ou reprise de chaînes ou de contenus de médias sanctionnés par l'Union européenne, notamment des médias russes.",
      non: "La décision évoque l'actualité internationale sans viser la diffusion d'un média sanctionné."
    },
    "accessibilite" => {
      question: "La décision reproche-t-elle un manquement aux obligations d'accessibilité aux personnes handicapées ?",
      oui: "Site public non accessible (RGAA, déclaration d'accessibilité), sous-titrage ou audiodescription insuffisants, ou éditeur n'ayant pas déposé à la BnF les fichiers numériques de ses œuvres au titre de l'exception handicap.",
      non: "La décision évoque des personnes handicapées seulement à propos de propos discriminatoires tenus à l'antenne."
    }
  }.freeze

  # Media types a ground can apply to. Grounds not listed apply to any media type.
  APPLICABLE_MEDIA = {
    "quotas_culturels" => %w[radio television video_a_la_demande]
  }.freeze

  def self.applies?(motif, media)
    APPLICABLE_MEDIA.fetch(motif, [media]).include?(media)
  end

  # One entry per ground, for Claude's instructions.
  def self.list
    DEFINITIONS.map do |id, d|
      "- #{id} : #{d[:question]}\n  Oui : #{d[:oui]}\n  Non : #{d[:non]}"
    end.join("\n")
  end
end
