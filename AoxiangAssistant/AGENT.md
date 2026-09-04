# OpenHarmony Application Template Guide

This is an OpenHarmony (stage-model) application template. **Only read the 3 files listed below** — do NOT glob, search, or read any other files unless you need to modify labels/icons.

## Must-read files (1 batch read)

| File | Why |
|------|-----|
| `entry/src/main/resources/base/profile/main_pages.json` | Page routing list — must update when adding pages |
| `entry/src/main/ets/pages/Index.ets` | @Entry @Component — rewrite this for the user's feature |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `windowStage.loadContent('pages/Index')` — must stay in sync with main_pages.json |

## On-demand files (only read when needed)

- `AppScope/resources/base/element/string.json` — key `"app_name"` → `"value": "MyApplication"`; only when renaming display name
- `entry/src/main/resources/base/element/string.json` — keys `"EntryAbility_label"` / `"EntryAbility_desc"`; only when changing ability label/description
- `AppScope/app.json5` — key `bundleName` under `app`; only when changing bundle ID

## Skip entirely

`EntryBackupAbility.ets`, `build-profile.json5`, `code-linter.json5`, `hvigor*`, `oh-package.json5`, `obfuscation-rules.txt`, `.gitignore`, `module.json5`, all media/color/float resources

## What to modify

1. `Index.ets` — rewrite page content; keep `@Entry @Component struct Index`
2. `main_pages.json` — add page paths as pages are created
3. `EntryAbility.ets` — update `loadContent()` if first page changes; must match main_pages.json first entry
4. `app_name` in `AppScope/resources/base/element/string.json` — if user wants a different display name
5. `bundleName` in `AppScope/app.json5` — if user wants a different bundle ID

## Invariants (do NOT change)

- `module.json5`: `module.type` = `"entry"`, `module.mainElement` = `"EntryAbility"` — no need to read this file, it rarely changes
- `module.json5`: `abilities[0].skills` must keep `entity.system.home` + `ohos.want.action.home`
- `EntryAbility.ets` must extend `UIAbility`
- `entry/build-profile.json5`: `apiType` must remain `"stageMode"`
