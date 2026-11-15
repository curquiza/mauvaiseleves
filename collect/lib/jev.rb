require "net/http"
require "json"
require "uri"
require_relative "env"
require_relative "motifs"

# Asks Jev (TypeSafe AI) the closed questions about a decision: type, kind of sanction,
# media type, and one yes/no question per ground (a decision can have several grounds).
#
# TypeSafe calls a yes/no question a "noul": the answer is the probability (0 to 1)
# that the statement is true. "noul" is the name required by their API.
class Jev
  URL = "https://api.typesafe.ai/v1/systemone"
  MODEL = "jev-1.14.0"
  YES = 0.7 # a ground is a clear yes above this probability
  NO = 0.3  # and a clear no below this one; in between, it is not settled

  MOTIFS = Motifs::DEFINITIONS
  PRICE_PER_MILLION_INPUT_TOKENS = 0.042 # dollars; output tokens are free

  # Media type id => description. A "choice" question: Jev picks exactly one.
  MEDIA = {
    "television" => "Service de télévision (chaîne de la TNT, du câble ou du satellite, chaîne locale).",
    "radio" => "Service de radio (FM, DAB+, radio numérique).",
    "video_a_la_demande" => "Service de médias audiovisuels à la demande (vidéo à la demande, télévision de rattrapage).",
    "en_ligne" => "Site internet, plateforme en ligne, réseau social ou plateforme de partage de vidéos.",
    "distributeur" => "Distributeur ou opérateur de diffusion (opérateur satellite, distributeur de chaînes), pas un éditeur de programmes.",
    "edition" => "Éditeur de livres ou d'œuvres écrites, pas un média audiovisuel (par exemple un éditeur tenu de déposer des fichiers numériques à la BnF).",
    "autre" => "Aucune des catégories précédentes."
  }.freeze
  # Type of measure. Also extracted by regex: the script compares both answers.
  TYPES = {
    "sanction" => "La décision prononce une sanction (amende, suspension, retrait d'autorisation, communiqué à l'antenne…).",
    "mise en demeure" => "La décision met l'éditeur en demeure de respecter ses obligations, sans prononcer de sanction.",
    "pas de sanction" => "La décision clôt une procédure de sanction sans prononcer de sanction (pas lieu de sanctionner, pas lieu à statuer).",
    "modification de sanction" => "La décision modifie une sanction prononcée par une décision antérieure.",
    "autre" => "Aucune des catégories précédentes (par exemple le retrait d'une mise en demeure)."
  }.freeze

  # Kind of sanction, only used when the type is "sanction".
  NATURES = {
    "amende" => "Sanction pécuniaire (amende).",
    "suspension" => "Suspension de l'autorisation ou de la diffusion d'un programme.",
    "retrait d'autorisation" => "Retrait ou abrogation de l'autorisation d'émettre.",
    "réduction de la durée d'autorisation" => "Réduction de la durée de l'autorisation.",
    "communiqué à l'antenne" => "Obligation de diffuser un communiqué à l'antenne.",
    "autre" => "Aucune des catégories précédentes, ou pas de sanction prononcée."
  }.freeze

  # Choice questions: id => [instructions, options].
  CHOICES = {
    "media" => ["Quel type de média est visé par cette décision de l'autorité de régulation de l'audiovisuel ?", MEDIA],
    "type" => ["Quel type de mesure cette décision de l'autorité de régulation de l'audiovisuel prononce-t-elle ?", TYPES],
    "nature" => ["Si cette décision prononce une sanction, de quelle nature est-elle ?", NATURES]
  }.freeze
  MIN_CONFIDENCE = 0.6 # below this, a choice answer deserves a human review

  attr_reader :calls, :input_tokens

  def initialize
    @calls = 0
    @input_tokens = 0
  end

  def cost
    input_tokens * PRICE_PER_MILLION_INPUT_TOKENS / 1_000_000
  end

  # Returns:
  #   { "motifs" => { ground => probability },
  #     "media" / "type" / "nature" => { "choice" => id, "confidence" => 0..1, "probabilities" => { id => probability } } }
  def classify(text)
    response = post({ state: text, model: MODEL, questions: questions })
    @calls += 1
    @input_tokens += response.dig("usage", "input_tokens").to_i
    answers = response.fetch("answers")
    result = { "motifs" => MOTIFS.keys.to_h { |motif| [motif, answers.dig(motif, "noul")] } }
    CHOICES.each_key { |id| result[id] = answers.fetch(id).slice("choice", "confidence", "probabilities") }
    result
  end

  private

  def questions
    motif_questions = MOTIFS.to_h do |motif, description|
      [motif, {
        type: "noul",
        instructions: "Cette décision de l'autorité de régulation de l'audiovisuel (Arcom ou CSA) reproche-t-elle à l'éditeur le manquement suivant ? #{description}"
      }]
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
