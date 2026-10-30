# Locale rules

## Scope and paths

The landing-site repository is normally the sibling `alikeapp.github.io` checkout.
Resolve its actual path or worktree before editing. English legal pages are at
`privacy.md` and `terms.md`; English landing data is `_data/en.yml`.

| Locale | Legal-page directory | Landing data | Address | Recently Deleted |
| --- | --- | --- | --- | --- |
| de | de/ | _data/de.yml | du | Zuletzt gelöscht |
| fr | fr/ | _data/fr.yml | vous | Supprimées récemment |
| es | es/ | _data/es.yml | tú | Eliminados |
| pt-BR | pt-br/ | _data/pt-BR.yml | você | Apagados |
| it | it/ | _data/it.yml | tu | Eliminati di recente |
| nl | nl/ | _data/nl.yml | je | Recent verwijderd |
| pl | pl/ | _data/pl.yml | informal ty | Ostatnio usunięte |
| tr | tr/ | _data/tr.yml | informal sen | Son Silinenler |
| zh-Hant | zh-hant/ | _data/zh-Hant.yml | 你 | 最近刪除 |

These album names follow the 2026-10-29 terminology record in
`Docs/Localization/native-review.md`. If that record changes, use its newer
verified terminology. For an unresolved platform term, consult the locale's
current Apple iPhone User Guide and record the source and date.

Use `arşiv` for the Turkish photo library and `截圖` for Traditional Chinese
screenshots. Use `apagar` for photos in pt-BR. Review metadata, buttons, and footer
text as well as legal prose for register drift. Keep the shipped app's control
labels where instructions name an actual control; inspect its catalog when unsure.

Do not add site pages for regional variants unless requested. English regional
listings use the existing English pages; fr-CA uses the existing French pages.

## Product facts

Do not freeze a locale count in this skill. Inspect current `knownRegions` in
`Alike/Alike.xcodeproj/project.pbxproj`, excluding `Base`, and localization entries
in the relevant current `.xcstrings` catalogs. A union of partial translations does
not establish complete support: compare coverage and the documented release scope.
If sources disagree, name the revisions and discrepancy before making a claim.

Keep the source free allowance, billing periods, and trial eligibility exact.
A historical task number or old skill description is not current product evidence.
