# App Store Release Notes Guidelines

The reader is a person with a full photo library and a busy day, not a developer.
They never saw the code, the cards or the commits. Every line answers one question
for them: "What is different for me, and where do I find it?"

The technical record of a release lives in the README's "What ships" section.
The store text is a separate piece of writing, not a summary of that section.

## Rules

| # | Rule | Why |
|---|---|---|
| 1 | Lead with what the person can do now, in "you" form: "You can…", "Swipe a photo to…". | People read for benefit, not for feature names. |
| 2 | Say where to find a new thing in one short clause: "add it from the widget gallery", "in a group, swipe a photo". | A feature nobody finds does not exist for them. |
| 3 | Use the app's own UI names from the string catalogs, in that locale. Never invent a label. | The words in the notes must match the words on screen. |
| 4 | No developer or system jargon: no API, framework, `systemExtraLargePortrait`, toolbar, rotor, render, overflow menu, pt, cross-fade, snapshot. Describe what the eye sees instead. | Typical users do not know what "UI" or "optimisation" means. |
| 5 | State an OS requirement once, in a closing line, not in every bullet. The opener may name the iOS version as the theme ("ready for iOS 27"). | "On iOS 27" five times reads like a spec sheet. |
| 6 | Fit the length to the update: 2–5 bullets, each one idea in 1–2 short sentences. | A small fix gets a sentence; a big release gets more, never a changelog. |
| 7 | Leave out what nobody notices: tests, refactors, internal routing, layout constants. Fold tiny polish into one "smoother" line, or drop it. | Noise hides the real news. |
| 8 | Name fixes by the symptom the person saw: "Fixed a crash when you opened a group", not "Fixed a ForEach isolation trap". | People remember the symptom, not the cause. |
| 9 | Never write "Bug fixes and performance improvements" or "better than ever". | Generic lines tell nothing and read as careless. |
| 10 | Keep a short, warm opener and the closing privacy and feedback lines. Thank people when the change came from their feedback. | The notes are the one dedicated place to talk to users; it can sound human. |
| 11 | No ticket IDs, card numbers, branch names, file paths, version-internal names or links other than Alike's own. | They mean nothing to the reader. |

## Shape

```
<One warm line: what this update is about for the person.>

- <What you can do now + where to find it.>
- <Next change, same form.>
- <Fix named by its symptom, if any.>

<OS requirement, once, if part of the update needs a newer iOS.>

<Privacy line.>

<Feedback line.>
```

## Words to replace

| Instead of | Write |
|---|---|
| widget family / extra-large portrait | the largest widget size / a tall widget |
| toolbar, overflow menu | the buttons at the top / the "More" menu |
| tinted / clear rendering mode | when your Home Screen icons are tinted or clear |
| VoiceOver rotor actions | works with VoiceOver |
| cross-fade transition | opens more smoothly |
| clips at 375 pt | is cut off on smaller iPhones |
| cluster | group (the app's own word) |

## Examples

- Weak: "On iOS 27, Rescan is pinned and grid columns and filter/sort fold into the overflow menu."
  Better: "The Cleanup buttons now fit on smaller iPhones."
- Weak: "Added systemExtraLargePortrait with topClusters."
  Better: "A new tall widget shows how much space you can free and your largest groups. Add it from the widget gallery."
- Weak: "Bugfixes."
  Better: "Fixed a crash when you opened a group's summary."

## QA Checklist

- Every bullet maps to a real, visible change in the range.
- Read each bullet aloud as a non-technical friend: would they know what changed and where?
- No word from the "Instead of" column, no code names, no OS version in more than one place.
- UI names match the string catalog in each locale.
- Length fits the store limit (4000 characters on the App Store) and the size of the update.

## Sources

- Ash Furrow, "Write Better iOS Release Notes": plain words, specific changes, thank users.
- RuStore developer blog, "What's New in your app listing": users, not the release process; no full changelog; no tracker references; no generic filler.
