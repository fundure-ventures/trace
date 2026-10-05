# Agent instructions

## Project memory

Trace keeps durable product knowledge in the repository:

| Location | Contains |
| --- | --- |
| [`FEATURES.md`](FEATURES.md) | Feature inventory, documentation template, UX principles, and testing philosophy |
| [`ADR.md`](ADR.md) | Decision inventory, documentation template, and principles for architectural rationale |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Development setup, commands, and engineering best practices only |
| [`DESIGN.md`](DESIGN.md) | Visual and interaction design guidelines only |

## Before changing behavior

1. Find the affected features in `FEATURES.md` and read their files.
2. Treat each **Rule** as a requirement. If the change breaks one, confirm with
   the user before proceeding and update the rule explicitly.
3. Find relevant decisions in `ADR.md` and read linked ADRs before changing
   an implementation they cover.

## After changing behavior

- Update the feature file in the same change: Solution, Touchpoints, Rules,
  FAQ, and Acceptance criteria must match the shipped behavior.
- New user-facing feature: add `memory/features/<feature-name>.md` and a row in
  `FEATURES.md`. Removed feature: delete both.
- New rule: describe its observable outcome under Acceptance criteria and add
  an appropriate guard (probe, test, or lint). If a guard is missing, disclose
  that in the change description, not in the feature's UX contract.
- New durable implementation decision: follow the template and principles in
  `ADR.md`, add the record in `memory/adr/`, and update its inventory.
- Keep feature files UX-focused. Commands and engineering practice belong in
  `DEVELOPMENT.md`; visual guidelines belong in `DESIGN.md`.
- Keep Acceptance criteria independent of test filenames, symbols, and
  coverage status. They describe what users should experience, not how the
  repository currently checks it.

## Code testing quality

The **Acceptance criteria** in the feature files listed in
[`FEATURES.md`](FEATURES.md) are the source of truth for test assertions.
Only assertions that protect those user-observable outcomes are relevant.

- Before writing or changing a test, identify the feature and acceptance
  criterion it protects. If an important outcome is missing, document it in
  the feature file first; do not invent requirements inside tests.
- Assert what the user can do and what happens, not internal calls, state
  structure, component layout, or current constants unless the criterion
  explicitly requires that observable result.
- Use the smallest reliable test or probe that demonstrates the outcome.
  Unit tests are useful when they protect an acceptance criterion; a unit
  test of a helper alone does not prove that the feature works end to end.
- Confirm each new test fails when the behavior it protects is broken, then
  restore the behavior. A passing test without this check is not evidence
  that it prevents the regression.
- Refactoring without changing acceptance criteria should not require
  rewriting assertions. Rewrite or remove tests that freeze implementation
  details instead of protecting the documented outcome.
- Keep tests independent of feature-file wording: link their intent to the
  criterion, but exercise behavior rather than matching documentation text.
