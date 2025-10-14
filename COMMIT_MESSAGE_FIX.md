# How to Fix Commit Messages to Follow Conventional Commits

The commits in this PR need to be updated to follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.

## Current Commits (need fixing)
1. `383911c` - "Initial plan" (empty commit)
2. `d19fb67` - "Add envsubst to tools image by building from source"
3. `2e98901` - "Add curl package explicitly to tools image"
4. `66bd628` - "docs: add note about commit message format update" (metadata commit)
5. `8ca6fc7` - "revert: remove temporary commit message documentation" (cleanup commit)
6. `627746a` - "docs: add instructions for fixing commit messages" (this file)

Note: Commits 1, 4, 5, and 6 should be dropped as they are metadata/process commits. Commits 2 and 3 should be squashed into a single commit with proper Conventional Commits format.

## Recommended Solution: Interactive Rebase

Run the following commands to rewrite the commit history:

```bash
# Start interactive rebase from the base commit
git rebase -i ed074a1

# In the editor that opens, change the commits as follows:
# - Line for 383911c: change 'pick' to 'drop' (remove empty commit)
# - Line for d19fb67: change 'pick' to 'reword' 
# - Line for 2e98901: change 'pick' to 'fixup' (squash into previous)
# - Line for 66bd628: change 'pick' to 'drop' (remove metadata commit)
# - Line for 8ca6fc7: change 'pick' to 'drop' (remove cleanup commit)
# - Line for 627746a: change 'pick' to 'drop' (remove this instruction file commit)

# When prompted to reword d19fb67, use this message:
feat(tools): add envsubst command to tools image

- Add multi-stage build to compile envsubst from gettext source (v0.22.5)
- Copy envsubst binary to final image
- Add curl package explicitly (was implicit dependency of gettext)
- Remove gettext package (replaced by built envsubst binary)
- Add verification test for envsubst
- Add gettext version to versions.yaml

Fixes #173

# After rebase completes, force push:
git push --force-with-lease origin copilot/implement-issues-173
```

## Alternative: Squash on Merge

When merging this PR, use GitHub's "Squash and merge" option with the commit message above.

## Conventional Commits Format Reference

Format: `<type>(<scope>): <description>`

- **type**: feat (new feature)
- **scope**: tools (the tools image)
- **description**: brief summary of changes
