# Arcom decisions collection

Fetches the sanctions and formal notices (*mises en demeure*) of Arcom (and the former CSA) published in the Journal officiel, through the Légifrance API, enriches them with Claude and Jev, and appends them to a private Google Sheet.

The Google Sheet is the reference database: each decision is identified by its `cid`, and the script only processes the decisions not yet in the sheet. Running it again, from any machine, never pays twice for the same decision.

## Setup

```fish
cd collect
bundle install
```

Create a `collect/.env` file (never committed) with:

```
# Légifrance API, from a sandbox application on https://piste.gouv.fr with the Légifrance API subscribed
PISTE_CLIENT_ID=...
PISTE_CLIENT_SECRET=...

# Claude API key, from https://platform.claude.com
ANTHROPIC_API_KEY=...

# Jev API key, from https://console.typesafe.ai/keys
TYPESAFE_API_KEY=...

# Id of the Google Sheet, found in its URL
GOOGLE_SHEET_ID=...
```

| Variable | Required | Description |
|---|---|---|
| `PISTE_CLIENT_ID`, `PISTE_CLIENT_SECRET` | yes | OAuth credentials of the PISTE application. |
| `ANTHROPIC_API_KEY` | yes | Used to extract services and programmes. |
| `CLAUDE_MODEL` | no | Claude model to use, `claude-sonnet-5-5` by default. |
| `TYPESAFE_API_KEY` | yes | Used to classify the grounds and the media type of each decision. |
| `GOOGLE_SHEET_ID` | yes | Id of the Google Sheet. |
| `GOOGLE_CREDENTIALS_JSON` | no | Content of the Google service account key. Used in GitHub Actions; locally, the key file below is used instead. |

### Google Sheet access

1. In Google Cloud, create a service account in a project where the Google Sheets API is enabled, and create a JSON key for it.
2. Save the key as `collect/credentials/google-service-account.json` (the `credentials/` folder is never committed).
3. Share the Google Sheet with the service account email, as Editor.

The sheet must have a tab named `v1` with the column names in row 3 (rows 1 and 2 are free for notes). The script writes each value in the column with the matching name, leaves the other columns empty, and stops if one of its columns is missing. Columns can be reordered and extra columns added.

## Usage

```fish
bundle exec ruby fetch_decisions.rb --dry-run          # list the new decisions, free (no Claude, no Jev, no writing)
bundle exec ruby fetch_decisions.rb --limit 10         # process the 10 most recent new decisions
bundle exec ruby fetch_decisions.rb --since 2026-11-01 # process the new decisions published since this date
bundle exec ruby fetch_decisions.rb --limit 10 --cost  # same, and show the tokens used and the real cost of Claude and Jev
bundle exec ruby fetch_decisions.rb                    # process all new decisions
```

By default, there is no limit and no start date: all new decisions are processed. Rows are written to the sheet in batches of 10, and pending rows are written even if the script fails, so that work already paid for is not lost.

## Where each column comes from

| Column | Source |
|---|---|
| `cid`, `date_decision`, `date_publication_jo`, `nor`, `lien_legifrance` | Légifrance API fields (`cid` is the unique id of each decision) |
| `texte_complet` | Full text of the decision (title, recitals and operative part), exactly as sent to Claude and Jev, so that it can be checked without calling the API |
| `date_ajout` | Date the row was added by the script |
| `numero`, `montant_euros` | Regular expressions on the title and the operative part (`montant_euros` falls back to Claude when the regex finds nothing) |
| `entite_visee`, `services`, `emissions` | Claude (extraction, to be reviewed). `entite_visee` is the company, association or administration targeted by the decision, written `[éditeur non nommé] du service …` when the decision does not name it |
| `type`, `type_probabilites`, `nature_sanction`, `nature_sanction_probabilites` | Jev (one choice each), cross-checked with regular expressions: any disagreement is reported in `a_verifier` |
| `media`, `media_probabilites` | Jev (one choice among `television`, `radio`, `video_a_la_demande`, `en_ligne`, `distributeur`, `edition`, `autre`) |
| `motifs`, `motifs_citations` | Claude: the grounds reproached by the decision, each with a supporting quote |
| `motifs_probabilites` | Jev: an independent probability for each ground (yes above 0.7, no below 0.3). Disagreements with Claude are reported in `a_verifier`; grounds that cannot apply to the media type (e.g. `creation_production` for a radio) are flagged |
| `a_verifier` | Reasons why a row deserves a manual review: missing regex matches, values found by Claude only, doubts reported by Claude, uncertain Jev answers, disagreements between Jev and the regular expressions |

Warnings (*mises en garde*) and reminder letters (*lettres de rappel*) are not published in the Journal officiel, so the script does not collect them.

Source: Légifrance (DILA), Licence Ouverte 2.0. Data from the API is not legally binding: only the signed PDF of the Journal officiel is authoritative.
