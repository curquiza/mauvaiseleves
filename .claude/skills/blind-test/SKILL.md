---
name: blind-test
description: Blind-test rows of the Arcom decisions Google Sheet. An independent agent fills the columns written by the script (regex, Claude, Jev) without seeing them, then compares with the script's values and reports. Use when the user asks for a blind test, a blind review or an independent check of rows in the sheet.
argument-hint: "<sheet rows, e.g. 4-13 or 4,7,12>"
---

# Blind test of sheet rows

An independent agent re-does, without seeing them, the columns that `collect/fetch_decisions.rb` filled, then compares its answers with the script's values. This measures how reliable the regex, Claude and Jev are, and finds weak rules.

## 1. Settle the exact rows first

The test must run on explicit sheet row numbers (the header is row 3, decisions start at row 4). Never default to the whole sheet.

- If the user gave rows (`$ARGUMENTS`, e.g. `4-13` or `4,7,12`), use them.
- Otherwise, ask which rows to test before doing anything else. To help, you may list the rows present (row number, `numero`, `date_ajout`) with a read-only call, but do not pick for the user.

## 2. Export the rows

From `collect/`, with an output directory in your scratchpad (never inside the repository):

```
bundle exec ruby ../.claude/skills/blind-test/export.rb --rows <rows> --out <scratchpad>/blind-test
```

It writes:
- `visible/ligne_<row>.txt`: cid, dates, NOR, link and full text of each decision. This is all the agent may see at first.
- `regles.md`: the rules given to the script (regex, Claude prompt, Jev questions and grounds), generated from the code.
- `hidden/valeurs_script.md`: the values filled by the script. The agent must not read it before the comparison.

Show the user the list of exported rows (row, `numero`) the script prints.

## 3. Blind pass

Spawn one general-purpose agent. Give it the paths of `visible/` and `regles.md` only (not the `hidden/` path), and ask it to:
- fill, for each decision, every column described in `regles.md` (choices with probabilities; grounds chosen with a supporting quote, plus an independent probability for each ground, keeping in the summary those ≥ 0.3), with a short quote justifying any non-obvious choice;
- list the cases where the rules seem ill-suited (missing ground or option, ambiguous definition, information impossible to extract);
- read nothing else, call no API, run no script.

## 4. Comparison

Once it has answered, send it (SendMessage) the path of `hidden/valeurs_script.md` and ask for:
1. a table per column: agreements out of N and the rows in disagreement;
2. the disagreements that matter, row by row, saying who is right and why, separating "the script is wrong" from "both readings hold";
3. how useful `a_verifier` was: relevant alerts, noise, script errors no alert caught;
4. a verdict per source (regex, Claude, Jev);
5. the most useful corrections to the script or rules, by priority.

## 5. Report

Before reporting a script error, check it yourself in the decision text or the sheet: an error can come from a bug (stale cell, missing text) rather than from a rule. Then report to the user, in their language: the summary table, the errors that matter, the verdict per source and the proposed corrections. Change nothing in the code or the sheet without the user's go-ahead.

The agent runs on the Claude Code account; it never uses the API keys in `collect/.env`.
