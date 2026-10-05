# Agent instructions

## Project memory

Trace keeps durable product knowledge in the repository:

| Location | Contains |
| --- | --- |
| [`FEATURES.md`](FEATURES.md) | Feature inventory, tags, file format, testing philosophy |
| [`memory/features/`](memory/features/) | One file per feature: problem, solution, touchpoints, rules, FAQ, acceptance criteria |
| [`memory/adr/`](memory/adr/README.md) | Durable implementation decisions and their reasons |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Development setup, commands, and engineering best practices only |
| [`DESIGN.md`](DESIGN.md) | Visual and interaction design guidelines only |

## Before changing behavior

1. Find the affected features in `FEATURES.md` and read their files.
2. Treat each **Rule** as a requirement. If the change breaks one, confirm with
   the user before proceeding and update the rule explicitly.
3. Read linked ADRs before changing an implementation they cover.

## After changing behavior

- Update the feature file in the same change: Solution, Touchpoints, Rules,
  FAQ, and Acceptance criteria must match the shipped behavior.
- New user-facing feature: add `memory/features/<feature-name>.md` and a row in
  `FEATURES.md`. Removed feature: delete both.
- New rule: describe its observable outcome under Acceptance criteria and add
  an appropriate guard (probe, test, or lint). If a guard is missing, disclose
  that in the change description, not in the feature's UX contract.
- New durable implementation decision: add an ADR in `memory/adr/` and its
  index row.
- Keep feature files UX-focused. Commands and engineering practice belong in
  `DEVELOPMENT.md`; visual guidelines belong in `DESIGN.md`.
- Keep Acceptance criteria independent of test filenames, symbols, and
  coverage status. They describe what users should experience, not how the
  repository currently checks it.

## Tests

Write tests that guard feature Rules, not implementation details. Do not add
tests that only restate current values or structure. When a test churns
without a rule change, fix it to target the rule or remove it.
