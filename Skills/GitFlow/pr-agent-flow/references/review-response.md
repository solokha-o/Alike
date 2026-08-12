# Responding to Review Notes

Use this after a reviewer leaves notes on an open PR. The goal is that every
note ends in one of three states — fixed, deliberately declined, or deferred —
and the reviewer can see which without re-reading the diff.

## 1. Read every note, not just the visible ones

Inline notes do **not** appear in the PR's comment list. `gh pr view 26 --json comments`
returns `[]` on a PR whose entire review is inline. Fetch both:

```bash
gh pr view <N> --json reviews --jq '.reviews[] | {author: .author.login, state, body}'
gh api repos/:owner/:repo/pulls/<N>/comments \
  --jq '.[] | {id, path, line, author: .user.login, in_reply_to_id, body}'
```

Keep each note's numeric `id`. Replies need it, and it is the only stable handle
on a thread.

## 2. Triage before fixing

Classify each note, in the rubric's severity order:

- **Accept** - the note is right; fix it.
- **Accept, different fix** - the problem is real, the suggested remedy is not
  the best one. Fix it your way and say why in the reply.
- **Decline** - the note is based on a wrong premise. Say so plainly with the
  evidence, and leave the code alone. Do not silently skip a note.
- **Defer** - real, but out of this PR's scope. Fix nothing, state where it will
  be handled.

Never resolve a note by explanation alone when the code is still risky, and
never let a "while I'm here" cleanup ride along in a review-response commit.

## 3. Fix one note per commit

One note, one commit, in `ios-git-flow` commit style. The reply then cites a
single SHA, and a reviewer who disagrees with one fix can drop one commit.

If a fix must spill into a second concern, say so in the reply rather than
widening the commit silently.

## 4. Prove the fix, do not assert it

A fix for a **test** note must be shown to catch what it previously missed:
break the thing the reviewer named, watch the test fail, restore, watch it pass.
Put that in the reply — a reviewer who flagged a false negative will not take
"fixed" on faith.

For copy and localization notes, quote the before and after values per locale.
For behavior notes, name the test that now covers the path.

Then run the validation the touched surface requires (`AGENTS.md` build gate for
compilable source; focused package tests otherwise).

## 5. Push before replying

A reply that says "fixed in <sha>" against an unpushed commit is a false report.
Push the branch first, then reply.

## 6. Reply on the thread, one reply per note

```bash
gh api repos/:owner/:repo/pulls/<N>/comments/<comment_id>/replies -f body='...'
```

Each reply carries: the commit SHA, what changed, and the evidence from step 4.
Keep it short enough to read in the thread.

## 7. Add one summary comment

```bash
gh pr comment <N> --body '...'
```

The summary carries what the threads cannot:

- a note-to-fix table, so the reviewer can see the whole set at once
- **anything changed beyond the notes**, called out as such, with why it was in
  scope
- **your own notes back** - a decision that looks like a mistake and will be
  "corrected" later, a premise in a note that was wrong, a risk the review did
  not raise
- validation actually run, including any deviation from the documented command
  (for example a substitute simulator when the pinned id is missing)

## 8. Leave the threads open

Resolving is the reviewer's call. Do not resolve threads, do not re-request
review, and do not merge on the strength of your own fixes.

## Anti-Patterns

- Replying "done" with no SHA and no evidence.
- One commit that answers four notes.
- Fixing the reviewer's example instead of the class of problem behind it.
- Widening a translation or copy fix into wording the source does not support.
- Quietly dropping a note that is inconvenient to answer.
- Claiming validation that was not run, or hiding that it ran on a substitute
  destination.
