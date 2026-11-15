require "net/http"
require "json"
require "uri"
require_relative "env"
require_relative "motifs"

# Asks Jev (TypeSafe AI) the closed questions about a decision: type, kind of sanction,
# media type, and one yes/no question per ground (a decision can have several grounds).
# Wording follows TypeSafe's guidance: short questions, options and yes/no criteria
# describing concrete situations, and a state split into named parts.
#
# TypeSafe calls a yes/no question a "noul": the answer is the probability (0 to 1)
# that the statement is true. "noul" is the name required by their API.
class Jev
  URL = "https://api.typesafe.ai/v1/systemone"
  MODEL = "jev-1.14.0"
  YES = 0.7 # a yes/no answer is a clear yes above this, and a choice is clear above this
  NO = 0.3  # a yes/no answer is a clear no below this; in between, it is not settled
  PRICE_PER_MILLION_INPUT_TOKENS = 0.042 # dollars; output tokens are free

  MEDIA = {
    "television" => "Une chaîne de télévision (TNT, câble, satellite ou chaîne locale).",
    "radio" => "Une radio (FM, DAB+ ou radio numérique).",
    "video_a_la_demande" => "Un service de vidéo à la demande ou de télévision de rattrapage.",
    "en_ligne" => "Un site internet, une plateforme en ligne, un réseau social ou une plateforme de partage de vidéos.",
    "distributeur" => "Un distributeur de chaînes ou un opérateur de diffusion, par exemple un opérateur satellite, qui n'édite pas lui-même les programmes.",
    "edition" => "Un éditeur de livres, par exemple tenu de déposer à la BnF les fichiers numériques de ses œuvres.",
    "autre" => "Aucune des catégories précédentes."
  }.freeze

  # Type of measure. Also extracted by regex: the script compares both answers.
  TYPES = {
    "sanction" => "Le dispositif prononce une sanction : amende, suspension, retrait d'autorisation ou communiqué à diffuser.",
    "mise en demeure" => "Le dispositif met en demeure de respecter des obligations, sans prononcer de sanction.",
    "clôture sans sanction" => "Le dispositif clôt une procédure de sanction en disant qu'il n'y a pas lieu de sanctionner ou de statuer.",
    "modification de sanction" => "Le dispositif modifie une sanction prononcée par une décision antérieure.",
    "autre" => "Aucune des catégories précédentes, par exemple le retrait d'une mise en demeure."
  }.freeze

  # Kind of sanction. Always asked; the script only reads it when the type is "sanction".
  NATURES = {
    "amende" => "Une sanction pécuniaire, c'est-à-dire une somme à payer.",
    "suspension" => "La suspension de l'autorisation ou de la diffusion d'un programme.",
    "retrait d'autorisation" => "Le retrait ou l'abrogation de l'autorisation d'émettre.",
    "réduction de la durée d'autorisation" => "La réduction de la durée de l'autorisation.",
    "communiqué à l'antenne" => "L'obligation de diffuser un communiqué à l'antenne.",
    "autre" => "Une sanction d'une autre nature que celles listées ci-dessus."
  }.freeze

  # Choice questions: id => [instructions, options]. The state's parts are named in backticks.
  CHOICES = {
    "media" => ["Quel type de média est visé par la décision ?", MEDIA],
    "type" => ["Quelle mesure le `dispositif` de la décision prononce-t-il ?", TYPES],
    "nature" => ["De quelle nature est la sanction prononcée dans le `dispositif` ?", NATURES]
  }.freeze

  attr_reader :calls, :input_tokens

  def initialize
    @calls = 0
    @input_tokens = 0
  end

  def cost
    input_tokens * PRICE_PER_MILLION_INPUT_TOKENS / 1_000_000
  end

  # Probability of the option Jev picked for a choice question.
  def self.top_probability(answer)
    answer["probabilities"][answer["choice"]].to_f
  end

  # state: { "titre", "considerants", "dispositif" }, from Extract.sections.
  # Returns:
  #   { "motifs" => { ground => probability },
  #     "media" / "type" / "nature" => { "choice" => id, "probabilities" => { id => probability } } }
  def classify(state)
    response = post({ state: state, model: MODEL, questions: questions })
    @calls += 1
    @input_tokens += response.dig("usage", "input_tokens").to_i
    answers = response.fetch("answers")
    result = { "motifs" => Motifs::DEFINITIONS.keys.to_h { |motif| [motif, answers.dig(motif, "noul")] } }
    CHOICES.each_key { |id| result[id] = answers.fetch(id).slice("choice", "probabilities") }
    result
  end

  private

  def questions
    motif_questions = Motifs::DEFINITIONS.to_h do |motif, d|
      [motif, { type: "noul", instructions: d[:question], criteria: { true: d[:oui], false: d[:non] } }]
    end
    choice_questions = CHOICES.transform_values do |(instructions, criteria)|
      { type: "choice", instructions: instructions, criteria: criteria }
    end
    motif_questions.merge(choice_questions)
  end

  def post(body, attempt: 1)
    uri = URI(URL)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
                                       "Authorization" => "Bearer #{Env.fetch('TYPESAFE_API_KEY')}")
    request.body = body.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.request(request) }

    case response.code
    when "200"
      JSON.parse(response.body)
    when "429", "500", "502", "503", "504"
      raise "Jev: HTTP #{response.code} after #{attempt} attempts" if attempt >= 4

      sleep(response["retry-after"]&.to_f || 2**attempt)
      post(body, attempt: attempt + 1)
    else
      raise "Jev: HTTP #{response.code}: #{response.body[0, 300]}"
    end
  end
end
