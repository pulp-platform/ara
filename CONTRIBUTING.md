# Styleguides

We are happy to accept pull requests and issues from any contributors. Please
note that we try to maintain a consistent quality standard. For a quick overview
please find some of the most important points below.

## Quick Overview

* Keep a clean commit history. This means no merge commits, and no long series
  of "fixup" patches (rebase or squash as appropriate). Structure work as a
  series of logically ordered, atomic patches. `git rebase -i` is your friend.
* Changes should only be made via pull request, with review. A pull request will
  be committed by a "committer" (an account listed in `CODEOWNERS`) once it has
  had an explicit positive review.
* Make sure you update the [CHANGELOG](CHANGELOG.md) when submitting a MR.
* When changes are restricted to a specific area, you are recommended to add a
  tag to the beginning of the first line of the commit message in square
  brackets e.g., "[apps] Fix bug #157".
* Do not force push. After rebasing, use `--force-with-lease` instead.
* Do not attempt to commit code with a non-Apache (or Solderpad for hardware)
  license without discussing first.
* If a relevant bug or tracking issue exists, reference it in the pull request
  and commits.

## Git Considerations

* Separate subject from body with a blank line
* Limit the subject line to 72 characters
* Capitalize the subject line
* Do not end the subject line with a period
* Use the imperative mood in the subject line
* Use the body to explain what and why vs. how
* Consider starting the commit message with an applicable emoji:
    * :sparkles: `:sparkles:` When introducing a new feature
    * :art: `:art:` Improving the format/structure of the code
    * :zap: `:zap:` When improving performance
    * :fire: `:fire` Removing code or files.
    * :memo: `:memo:` When writing docs
    * :bug: `:bug:` When fixing a bug
    * :fire: `:fire:` When removing code or files
    * :wastebasket: `:wastebasket:` When removing code or files
    * :green_heart: `:green_heart:` When fixing the CI build
    * :construction_worker: `:construction_worker:` Adding CI build system
    * :white_check_mark: `:white_check_mark:` When adding tests
    * :lock: `:lock:` When dealing with security
    * :arrow_up: `:arrow_up:` When upgrading dependencies
    * :arrow_down: `:arrow_down:` When downgrading dependencies
    * :rotating_light: `:rotating_light:` When removing linter warnings
    * :pencil2: `:pencil2:` Fixing typos
    * :recycle: `:recycle:` Refactoring code.
    * :boom: `:boom:` Introducing breaking changes
    * :truck: `:truck:` Moving or renaming files.
    * :space_invader: `:space_invader:` When fixing something synthesis related
    * :ok_hand: `:ok_hand` Updating code due to code review changes
    * :building_construction: `:building_construction:` Making architectural changes.

For further information please see the excellent
[guide](https://chris.beams.io/posts/git-commit/) by Chris Beams.

## Code Style

Consistent code style is important. We try to follow existing style conventions
as much as possible:

* For RTL we use [lowRISC's SystemVerilog style
  guidelines](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md).
* For C/C++ we follow [LLVM's style guide](https://llvm.org/docs/CodingStandards.html).
