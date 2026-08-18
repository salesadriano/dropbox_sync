# Documentation Sync — Strategy Quick Reference

## Decision: What to Update

```
Change made → Ask:
  1. Does this change the public interface (API, CLI, config schema)?
     → Yes → Update all consumer-facing docs (README, API reference, guides)
  2. Does this change the architecture or key decisions?
     → Yes → Update architecture docs, ADRs, System Design
  3. Does this break any documented behavior?
     → Yes → Update affected docs before merging
  4. Does this affect team process (CI, deployment, testing)?
     → Yes → Update runbooks and contributing guides
  5. Minor internal refactor with no behavior change?
     → No doc update needed
```

## Layer-by-Layer Update Map

| Doc Type | Update When | Owner |
|----------|-------------|-------|
| `README.md` | Public setup or usage changes | Any contributor |
| `CONTRIBUTING.md` | Dev workflow, tools, conventions change | Tech Lead |
| API reference | Endpoint added/changed/removed | Developer who made the change |
| Architecture/System Design | Component responsibility or integration changes | Business Analyst + Tech Lead |
| ADRs | New architectural decision made | Tech Lead |
| Runbooks | Operational procedure changes | DevOps / Tech Lead |
| Changelog | Every user-visible change | Developer |

## Staleness Detection

```bash
# Find docs that reference deleted files
git log --diff-filter=D --name-only --pretty=format: HEAD~20 | sort -u

# Find docs not touched in 90 days in an active area
git log --since="90 days ago" --name-only -- docs/ | sort | uniq -c | sort -n | head -20

# Find docs referencing renamed symbols
grep -r "OldClassName" docs/
```

## Anti-Patterns to Avoid

```
❌ "We'll update docs after the sprint"
   → Docs diverge, can never be caught up atomically

❌ Updating docs without reading what they currently say
   → Risk of contradictions and duplications

❌ Updating every doc for every change
   → Noise obscures signal; trivial docs become stale anyway

❌ Keeping outdated sections "for reference"
   → Delete or archive — outdated info is worse than no info
```

## Atomic Doc Sync Checklist

Before closing a PR that changes behavior:

```markdown
- [ ] README reflects new behavior (if user-visible)
- [ ] API/interface docs updated (if contract changed)
- [ ] Architecture docs updated (if structure changed)
- [ ] Examples and code snippets still compile/run
- [ ] No orphaned references to deleted/renamed things
- [ ] Changelog entry added for user-facing changes
```
