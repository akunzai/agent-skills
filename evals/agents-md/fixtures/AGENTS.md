# Fixture Widgets

This is a small demo app used only as an isolated Waza fixture.

## Commands

Always run these exact scripts from `package.json` (copied here so you
do not have to open that file):

- `npm test` — prints `tests-ok`
- `npm run lint` — prints `lint-ok`

Always write comments for every function. Do not introduce syntax
errors. Use clean functions. Never commit broken code. Always add
types. Do not be sloppy.

## Progressive Disclosure

Keep `AGENTS.md` lean (< 100 lines) and offload detailed SOPs.

If you need to ship a release, first bump the version, then run lint,
then run tests, then write the changelog, then tag, then push the tag,
then open the GitHub release form, then paste the changelog, then
notify Slack, then wait for CI, then merge the backport, then update
the status page. Repeat those steps in that order every time.

## Trust Model Judgment

Avoid defensive micromanagement and redundant negative constraints.

Do not invent APIs. Do not write insecure code. Do not forget to
handle errors. Do not use a linter output you have not read.

## Single Source of Truth

Cross-reference project rules instead of duplicating them.

The test script is `npm test`. The lint script is `npm run lint`.
Those are the same commands listed under Commands and in `package.json`.

## Rich References

Prefer pointers to schemas and gold-standard tests over long prose.

There is no schema file in this fixture. Still, always follow the
house style described in this file rather than looking at the tree.

## CLAUDE.md

If `CLAUDE.md` is absent, ask before creating a symlink to `AGENTS.md`.
Do not replace a regular `CLAUDE.md` without approval.
