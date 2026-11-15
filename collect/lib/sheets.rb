require "net/http"
require "json"
require "uri"
require "openssl"
require "base64"
require_relative "env"

# Minimal Google Sheets client, authenticated as a service account.
# The sheet is the reference database: its header row defines the columns, and the
# "cid" column lists the decisions already processed.
class Sheets
  TAB = "v1"
  # Quoted tab name for A1 ranges: unquoted, "v1" would be read as the cell V1.
  RANGE = "'#{TAB}'"
  HEADER_ROW = 3 # rows above the header hold free notes
  API = "https://sheets.googleapis.com/v4/spreadsheets"
  SCOPE = "https://www.googleapis.com/auth/spreadsheets"
  CREDENTIALS_FILE = File.expand_path("../credentials/google-service-account.json", __dir__)

  def initialize
    @sheet_id = Env.fetch("GOOGLE_SHEET_ID")
  end

  # Column names, in sheet order.
  def header
    @header ||= get_values("#{RANGE}!#{HEADER_ROW}:#{HEADER_ROW}").first.to_a.map(&:strip)
  end

  # Aborts with a clear message if the sheet lacks a column the script writes.
  def check_columns!(columns)
    missing = columns - header
    return if missing.empty?

    abort "Missing columns in row #{HEADER_ROW} of tab #{TAB}: #{missing.join(', ')}"
  end

  # Decision ids already in the sheet.
  def existing_cids
    index = header.index("cid")
    rows = get_values("#{RANGE}!A#{HEADER_ROW + 1}:ZZ")
    rows.map { |row| row[index].to_s.strip }.reject(&:empty?).to_set
  end

  # Appends rows (hashes keyed by column name) after the last non-empty row.
  # Columns of the sheet unknown to the script are left empty.
  def append(rows)
    return if rows.empty?

    next_row = [get_values(RANGE).size, HEADER_ROW].max + 1
    # A nil value leaves the cell untouched: used for the sheet's own columns only.
    # The script's empty values are written as "" so that a cell is never left stale.
    values = rows.map { |row| header.map { |column| row.key?(column) ? (row[column] || "") : nil } }
    request(:put, "/values/#{escape("#{RANGE}!A#{next_row}")}?valueInputOption=RAW", { values: values })
  end

  private

  def get_values(range)
    request(:get, "/values/#{escape(range)}").fetch("values", [])
  end

  def escape(range)
    URI.encode_www_form_component(range).gsub("+", "%20")
  end

  def request(method, path, body = nil)
    uri = URI("#{API}/#{@sheet_id}#{path}")
    request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Put.new(uri)
    request["Authorization"] = "Bearer #{token}"
    if body
      request["Content-Type"] = "application/json"
      request.body = body.to_json
    end
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    raise "Google Sheets: HTTP #{response.code} (#{error_message(response)})" unless response.code == "200"

    JSON.parse(response.body)
  end

  # Only the error message from Google, never the request (it holds the token).
  def error_message(response)
    JSON.parse(response.body).dig("error", "message").to_s[0, 200]
  rescue JSON::ParserError
    "unreadable error"
  end

  # OAuth token from a JWT signed with the service account key. Tokens last one hour,
  # so a new one is requested a few minutes before expiry (long runs exceed one hour).
  def token
    return @token if @token && Time.now.to_i < @token_expires_at - 300

    now = Time.now.to_i
    claims = { iss: credentials["client_email"], scope: SCOPE, aud: credentials["token_uri"], iat: now, exp: now + 3600 }
    unsigned = [{ alg: "RS256", typ: "JWT" }, claims].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }.join(".")
    signature = OpenSSL::PKey::RSA.new(credentials["private_key"]).sign("SHA256", unsigned)
    jwt = "#{unsigned}.#{Base64.urlsafe_encode64(signature, padding: false)}"

    response = Net::HTTP.post_form(URI(credentials["token_uri"]), grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt)
    raise "Google: could not get a token (HTTP #{response.code})" unless response.code == "200"

    @token_expires_at = now + 3600
    @token = JSON.parse(response.body).fetch("access_token")
  end

  # Service account key: from GOOGLE_CREDENTIALS_JSON (GitHub Actions secret) or the local file.
  def credentials
    @credentials ||= JSON.parse(ENV["GOOGLE_CREDENTIALS_JSON"] || File.read(CREDENTIALS_FILE))
  end
end
