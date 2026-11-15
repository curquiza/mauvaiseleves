# mauvaiseleves

Collects the decisions of Arcom (French audiovisual regulator, formerly CSA) published in the Journal officiel, through the Légifrance API (PISTE portal), enriches them with Claude and Jev (TypeSafe AI), and writes them to a private Google Sheet. A front-end will come later.

- `collect/`: Ruby data collection scripts (see `collect/README.md`).

## Security rules (public repository)

The repository is public, and so are the GitHub Actions logs.

- Never put a secret (API key, OAuth client secret, token, Google service account JSON) in the code, in a commit, in a log, in an error message or in a test fixture.
- Secrets live only in `collect/.env` and `collect/credentials/` locally (both git-ignored), and in GitHub Actions secrets for the scheduled job.
- Never print environment variables, HTTP request headers, OAuth tokens or raw API responses that could contain them. Logs only show decision titles and counts.
- Before each commit, check `git status` and the staged diff for secrets.
- The Google Sheet ID is not a secret, but the Sheet stays private: do not log its content.

## Legal rules

- Never scrape arcom.fr: its robots.txt forbids automated access. It may only be read manually by a human, who can paste content into the project.
- Data from Légifrance is under Licence Ouverte 2.0: always cite the source (Légifrance / DILA) and keep the link to each decision.
- GDPR: do not add the names of people (presenters, guests) to the data. Decisions published in the Journal officiel are already pseudonymized ("M. X.", "l'invitée"); keep them that way.
- API data is not legally binding: only the signed PDF of the Journal officiel is authoritative.

## Conventions

- Data collection scripts (`collect/`): Ruby, simple and readable, standard library when possible.
- Code comments and README in English. Data (CSV/Sheet column names, values, prompts sent to Claude and Jev) in French, like the decisions.
- In Markdown, never break a line in the middle of a sentence.
- LLM calls cost money: never run the full collection without the user's go-ahead, and test with `--limit` first.
