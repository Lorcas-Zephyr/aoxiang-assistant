## Change classification

Choose exactly one primary classification. This is checked by CI. If the change spans categories, choose the highest-risk category and explain the other impact below.

- [ ] Platform-only: Android or iOS implementation/UI behavior with no shared contract change
- [ ] Shared behavior: parsing, normalization, scheduling, diffing, persistence semantics, or another Android/iOS behavior change
- [ ] Wire/contract breaking: incompatible JSON/API/enum/ID/date-time change, or a migration that cannot read the previous contract (requires a new schema/golden version and migration)

## Contract and compatibility

- Baseline or contract version affected: `v2.2.2` / `golden/v1` / other: <!-- fill in -->
- Does this change alter observable Android/iOS behavior? <!-- yes/no + details -->
- Does this change alter exported JSON or a wire/API interpretation? <!-- yes/no + details -->
- New `schemaVersion` / `golden/vN` for a breaking change: <!-- required for breaking changes; otherwise "not applicable" -->
- Rollback or downgrade behavior: <!-- describe, or write "unchanged" -->

## Required evidence

- [ ] I added or updated a sanitized golden fixture when shared behavior changed.
- [ ] `expected.json` was reviewed independently from the implementation output.
- [ ] For a wire/contract breaking change, I increased `schemaVersion`, created a new `golden/vN`, retained the previous fixtures, and added migration tests.
- [ ] I ran the Android contract tests and recorded the result.
- [ ] I ran the Swift contract tests; no pending adapter is described as behavior-compatible.
- [ ] I updated the changelog/release notes when user-visible behavior changed.
- [ ] I documented any intentional Android/iOS output difference.

## Security and privacy

- [ ] No password, Cookie, token, `Authorization` header, SMS verification code, session data, or real personal/dormitory identifier was added to source, fixtures, logs, screenshots, or test output.
- [ ] All fixture inputs are sanitized and synthetic or otherwise approved for repository storage.
- [ ] I checked that failure output does not print credentials or WebView session data.

## Validation notes

<!-- Include commands, fixture IDs, migration versions, known limitations, and a rollback plan. -->
