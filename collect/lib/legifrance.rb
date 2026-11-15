require "net/http"
require "json"
require "uri"
require_relative "env"

# Minimal client for the Légifrance API (PISTE portal).
class Legifrance
  OAUTH_URL = "https://sandbox-oauth.piste.gouv.fr/api/oauth/token"
  API_URL = "https://sandbox-api.piste.gouv.fr/dila/legifrance/lf-engine-app"

  EMETTEURS = [
    "AUTORITE DE REGULATION DE LA COMMUNICATION AUDIOVISUELLE ET NUMERIQUE",
    "CONSEIL SUPERIEUR DE L'AUDIOVISUEL"
  ].freeze

  PAGE_SIZE = 100
  PAUSE = 0.3 # seconds between calls, to stay under the rate limits

  # All JORF texts from Arcom and CSA whose title contains the exact expression.
  def search_titles(expression)
    results = []
    page = 1
    loop do
      body = post("/search", search_body(expression, page))
      results.concat(body["results"])
      break if body["results"].empty? || results.size >= body["totalResultNumber"]

      page += 1
    end
    results
  end

  # Full text of a decision.
  def decision(cid)
    post("/consult/jorf", { textCid: cid })
  end

  private

  def search_body(expression, page)
    {
      fond: "JORF",
      recherche: {
        champs: [{
          typeChamp: "TITLE",
          operateur: "ET",
          criteres: [{ valeur: expression, typeRecherche: "EXACTE", operateur: "ET" }]
        }],
        filtres: [{ facette: "EMETTEUR", valeurs: EMETTEURS }],
        pageNumber: page,
        pageSize: PAGE_SIZE,
        operateur: "ET",
        sort: "SIGNATURE_DATE_DESC",
        typePagination: "DEFAUT"
      }
    }
  end

  def post(path, body, attempt: 1)
    uri = URI(API_URL + path)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{token}")
    request.body = body.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.request(request) }
    sleep PAUSE

    case response.code
    when "200"
      JSON.parse(response.body)
    when "401"
      raise "Légifrance: access denied (401)" if attempt > 1

      @token = nil # expired token: ask for a new one
      post(path, body, attempt: attempt + 1)
    when "429", "500", "502", "503", "504"
      raise "Légifrance: HTTP #{response.code} after #{attempt} attempts" if attempt >= 4

      sleep 2**attempt
      post(path, body, attempt: attempt + 1)
    else
      raise "Légifrance: HTTP #{response.code} on #{path}: #{response.body[0, 300]}"
    end
  end

  def token
    @token ||= begin
      response = Net::HTTP.post_form(
        URI(OAUTH_URL),
        grant_type: "client_credentials",
        client_id: Env.fetch("PISTE_CLIENT_ID"),
        client_secret: Env.fetch("PISTE_CLIENT_SECRET"),
        scope: "openid"
      )
      raise "PISTE: could not get a token (HTTP #{response.code})" unless response.code == "200"

      JSON.parse(response.body).fetch("access_token")
    end
  end
end
