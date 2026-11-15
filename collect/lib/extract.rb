require "date"

# Regex extraction: only what follows a fixed wording in the decision titles and
# operative part. No interpretation here.
module Extract
  # Strips HTML and normalizes whitespace.
  def self.plain(html)
    html.to_s
        .gsub(/<br\s*\/?>|<\/p>/i, "\n")
        .gsub(/<[^>]+>/, " ")
        .gsub("&nbsp;", " ")
        .gsub(/[ \t  ]+/, " ")
        .gsub(/ *\n */, "\n")
        .gsub(/\n{2,}/, "\n")
        .strip
  end

  # Title without the "CONSEIL SUPERIEUR DE L'AUDIOVISUEL (CSA)" header of old texts.
  def self.title(raw)
    plain(raw).gsub(/\s+/, " ").sub(/\ACONSEIL SUPERIEUR DE L.AUDIOVISUEL \(CSA\)\s*/, "").strip
  end

  # Légifrance dates are milliseconds since 1970, at midnight UTC.
  def self.date(milliseconds)
    return nil if milliseconds.nil?

    Time.at(milliseconds / 1000).utc.to_date.iso8601
  end

  def self.number(title)
    title[/D[ée]cision\s+n[°o]\s*([\w-]+)/, 1]
  end

  # Article 1 of the decision: the operative part, where the measure is stated.
  # Some decisions store their recitals in an unnumbered "article": skip it.
  def self.dispositif(decision)
    article = decision["articles"].to_a.select { |a| a["num"].to_i.positive? }.min_by { |a| a["num"].to_i }
    plain(article && article["content"]).gsub(/\s+/, " ")
  end

  # Full text of the decision: title, recitals and every article, in order.
  def self.full_text(decision)
    articles = decision["articles"].to_a.map { |a| plain(a["content"]) }
    [title(decision["title"]), plain(decision["visa"]), *articles].reject(&:empty?).join("\n\n")
  end

  # Type of measure, from the title and, when needed, the operative part.
  def self.measure_type(title, dispositif)
    case title
    when /en demeure/i
      "mise en demeure"
    when /modification de la d[ée]cision.*sanction/i
      "modification de sanction"
    when /mettant fin à la procédure de sanction/i
      "pas de sanction"
    when /procédures? de sanction/i
      outcome_of_procedure(dispositif)
    when /sanction/i
      "sanction"
    end
  end

  def self.outcome_of_procedure(dispositif)
    case dispositif
    when /pas lieu (de prononcer|à statuer)/i then "pas de sanction"
    when /sanction|abrog|retir|suspen/i then "sanction"
    else "à vérifier"
    end
  end

  # Kind of sanction, from the operative part.
  def self.sanction_kind(dispositif, title)
    return "communiqué à l'antenne" if title =~ /insertion d.un communiqué/i

    case dispositif
    when /sanction pécuniaire/i then "amende"
    when /suspen/i then "suspension"
    when /abrog|retir|retrait/i then "retrait d'autorisation"
    when /réduction de la durée/i then "réduction de la durée d'autorisation"
    when /communiqué/i then "communiqué à l'antenne"
    else "autre"
    end
  end

  # Amount in euros, from the wording "d'un montant de 200 000 euros".
  def self.amount(dispositif)
    match = dispositif[/montant de ([\d\s.]+?)\s*(?:euros|€)/i, 1]
    match&.gsub(/[^\d]/, "")&.to_i
  end

  # True if the amount is written in the text, whatever the thousands separator.
  def self.amount_in_text?(amount, text)
    text.gsub(/(?<=\d)[\s.  ](?=\d{3})/, "").include?(amount.to_s)
  end

  # NOR identifiers start with "RCA" for Arcom, "CSA" for the former CSA.
  def self.emitter(nor)
    nor.to_s.start_with?("RCA") ? "Arcom" : "CSA"
  end
end
