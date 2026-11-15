require "anthropic"
require "json"
require_relative "env"
require_relative "motifs"

# Extracts with Claude what has no fixed wording (entity, services, programmes, amount)
# and the grounds of the decision, each with a supporting quote. Jev judges the same
# grounds independently: the script compares both.
class Claude
  MODEL = ENV.fetch("CLAUDE_MODEL", "claude-sonnet-5-5")
  # Effort by text length, in characters: low by default, medium then high for long decisions.
  MEDIUM_TEXT = 15_000
  HIGH_TEXT = 30_000

  # Dollars per million tokens. Cache writes cost 1.25 times the input price.
  PRICES = {
    "claude-sonnet-5-5" => { input: 2.0, output: 10.0, cache_read: 0.20, cache_write: 2.50 },
    "claude-opus-5-5" => { input: 4.0, output: 20.0, cache_read: 0.20, cache_write: 5.00 }
  }.freeze

  INSTRUCTIONS = <<~PROMPT
    Tu lis une décision de l'Arcom (ou de l'ancien CSA) publiée au Journal officiel.
    Extrais uniquement ce qui est écrit explicitement dans le texte :
    - services : le ou les services concernés par la décision (nom de la chaîne de télévision,
      de la radio ou du site), tels qu'écrits dans le texte, sans la société éditrice. Ils sont
      souvent entre guillemets ; un nom de site peut aussi être écrit sans guillemets.
    - emissions : les émissions ou séquences mises en cause, avec leurs dates de diffusion
      au format AAAA-MM-JJ (une période s'écrit AAAA-MM-JJ/AAAA-MM-JJ). Quand la décision porte
      sur l'ensemble des programmes d'une période (par exemple le pluralisme sur un mois), liste
      les émissions qu'elle cite en exemple, avec leurs dates. N'inclus pas les émissions citées
      au titre de décisions antérieures, ni les dates qui n'apparaissent que dans une demande
      d'enregistrements ou de documents. Liste toutes les émissions et toutes les dates citées,
      sans en omettre ni les résumer. Si le manquement porte sur l'ensemble du programme
      d'une période sans qu'aucune émission soit citée (par exemple des quotas de chansons),
      laisse la liste vide.
    - entite_visee : l'entité visée par la décision (société, association, administration…),
      c'est-à-dire l'éditeur ou le responsable, pas le nom du service. Écris son nom sans article
      ni forme juridique en tête : « Radio France » et non « la société nationale de programme
      Radio France », « Lyon Media Plus » et non « SARL Lyon Media Plus », sauf si ces mots font
      partie du nom (« Société d'exploitation d'un service d'information », « Association pour
      le développement… »). N'ajoute pas de sigle entre parenthèses. Si la décision ne la nomme pas (par exemple « la personne éditrice
      du service xfrenchies.com »), écris « [éditeur non nommé] du service xfrenchies.com » :
      ce n'est pas un doute.
    - montant : le montant de la sanction pécuniaire prononcée par la décision, tel qu'il est
      écrit, avec sa devise : « 200 000 € », ou « 200 000 F » pour les francs. Ne convertis
      jamais les francs en euros. null si la décision ne prononce pas d'amende.
    - motifs : les manquements que la décision reproche, choisis dans la liste ci-dessous
      (un ou plusieurs). Ne retiens un motif que si la décision le reproche, pas s'il est
      seulement évoqué. Si la décision clôt une procédure sans sanction (pas lieu de
      sanctionner ou de statuer), laisse la liste vide : ce n'est pas un doute.
    - resume : une phrase de 25 mots maximum qui décrit concrètement le manquement que la
      décision reproche (ce qui a été diffusé ou fait), sans répéter le nom de l'éditeur.
      Reformule uniquement ce que la décision établit, sans jugement ni adjectif ajouté. Par
      exemple : « Publicité clandestine pour une marque de boisson dans une émission de jeux. »
      Ne mentionne ni la mesure prononcée, ni le retrait ou l'abrogation de l'autorisation, ni
      la suite de la procédure. Pour une procédure close sans sanction, décris ce qui était
      reproché dans la procédure (« Il était reproché… »), et ne présente jamais comme établi
      un manquement que la décision écarte.
    - doute : si une de ces informations est ambiguë ou incertaine, explique en une phrase
      courte laquelle et pourquoi. Sinon, laisse une chaîne vide. Une valeur vide ou null qui
      applique ces règles (pas d'amende, aucune émission citée, aucun motif) n'est pas un doute :
      ne la justifie pas.
    N'invente rien. Laisse une liste vide si l'information n'est pas dans le texte.
    N'inclus aucun nom de personne. Les décisions remplacent souvent les noms par « M. X. »,
    « l'invitée », etc. : c'est normal, ce n'est pas un doute. Si une information demandée
    contient un nom anonymisé (« [X] », « [Mme X] », « M. X. »…), remplace ce nom par
    « [nom anonymisé] » : « [X] et vous » devient « [nom anonymisé] et vous ».

    Liste des motifs :
    #{Motifs.list}
  PROMPT

  SCHEMA = {
    type: "object",
    properties: {
      services: { type: "array", items: { type: "string" } },
      emissions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            titre: { type: "string" },
            dates_diffusion: { type: "array", items: { type: "string" } }
          },
          required: %w[titre dates_diffusion],
          additionalProperties: false
        }
      },
      entite_visee: { type: "string" },
      montant: { anyOf: [{ type: "string" }, { type: "null" }] },
      motifs: { type: "array", items: { type: "string", enum: Motifs::DEFINITIONS.keys } },
      resume: { type: "string" },
      doute: { type: "string" }
    },
    required: %w[services emissions entite_visee montant motifs resume doute],
    additionalProperties: false
  }.freeze

  attr_reader :calls, :usage

  def initialize
    @client = Anthropic::Client.new(api_key: Env.fetch("ANTHROPIC_API_KEY"))
    @calls = 0
    @usage = { input: 0, output: 0, cache_read: 0, cache_write: 0 }
  end

  # Cost in dollars of the calls made so far, or nil for a model without known prices.
  def cost
    prices = PRICES[MODEL] or return nil
    usage.sum { |kind, tokens| tokens * prices[kind] / 1_000_000 }
  end

  # Returns { "services" => [...], "emissions" => [{ "titre", "dates_diffusion" }], "entite_visee" => "...",
  #           "montant" => "200 000 €" or nil, "motifs" => ["haine_discrimination", ...], "resume" => "...", "doute" => "..." }.
  def extract(cid, text)
    message = @client.messages.create(
      model: MODEL.to_sym,
      max_tokens: 16_000, # room for thinking at high effort
      output_config: { effort: effort(text), format_: { type: :json_schema, schema: SCHEMA } },
      # The instructions are the same for every decision: caching them makes repeated calls cheaper.
      system_: [{ type: "text", text: INSTRUCTIONS, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: text }]
    )
    record_usage(message.usage)
    raise "Claude refused to process #{cid}" if message.stop_reason == :refusal

    JSON.parse(message.content.find { |block| block.type == :text }.text)
  end

  private

  # Long decisions (e.g. a month of programmes reviewed for pluralism) list many programmes:
  # at low effort, Claude tends to shorten the list. They are rare, so more effort costs little.
  def effort(text)
    return :high if text.size > HIGH_TEXT
    return :medium if text.size > MEDIUM_TEXT

    :low
  end

  def record_usage(usage)
    @calls += 1
    @usage[:input] += usage.input_tokens.to_i
    @usage[:output] += usage.output_tokens.to_i
    @usage[:cache_read] += usage.cache_read_input_tokens.to_i
    @usage[:cache_write] += usage.cache_creation_input_tokens.to_i
  end
end
