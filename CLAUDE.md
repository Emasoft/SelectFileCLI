# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## General Development Guidelines and Rules
- *CRITICAL*: when reading the lines of the source files, do not read just few lines like you usually do. Instead always read all the lines of the file (until you reach the limit of available context memory). No matter what is the situation, searching or editing a file, ALWAYS OBEY TO THIS RULE!!!.
- *CRITICAL*: do not ever do unplanned things or take decisions without asking the user first. All non trivial changes to the code must be planned first, approved by the user, and added to the tasks_checklist.md first. Unless something was specifically instructed by the user, you must not do it. Do not make changes to the codebase without duscussing those with the user first and get those approved. Be conservative and act on a strict need-to-be-changed basis.
- *CRITICAL*: COMMIT AFTER EACH CHANGE TO THE CODE, NO MATTER HOW SMALL!!!
- *CRITICAL*: after receiving instructions from the user, before you proceed, confirm if you understand and tell the user your plan. If instead you do not understand something, or if there are choices to make, ask the user to clarify, then tell the user your plan. Do not proceed with the plan if the user does not approve it.
- *CRITICAL*: **Auto-Lint after changes**: Always run the linters (like ruff, shellcheck, mypy, yamllint, eslint, etc.) after any changes to the code files! ALWAYS DO IT BEFORE COMMITTING!!
- *CRITICAL*: Never use pip. Use `uv pip <commands>` instead. Consider pip deprecated in favor of uv pip.
- *CRITICAL*: Never use GREP! Use RIPGREP instead!
- *CRITICAL*: Never spawn multiple subagents that need to use git at the same time. It can cause conflicting git operations that lead to repo corruption.
- be extremely meticulous and accurate. always check twice any line of code for errors when you edit it.
- never output code that is abridged or with parts replaced by placeholder comments like `# ... rest of the code ...`, `# ... rest of the function as before ...`, `# ... rest of the code remains the same ...`, or similar. You are not chatting. The code you output is going to be saved and linted, so omitting parts of it will cause errors and broken files.
- Be conservative. only change the code that it is strictly necessary to change to implement a feature or fix an issue. Do not change anything else. You must report the user if there is a way to improve certain parts of the code, but do not attempt to do it unless the user explicitly asks you to. 
- when fixing the code, if you find that there are multiple possible solutions, do not start immediately but first present the user all the options and ask him to choose the one to try. For trivial bugs you don't need to do this, of course.
- never remove unused code or variables unless they are wrong, since the program is a WIP and those unused parts are likely going to be developed and used in the future. The only exception is if the user explicitly tells you to do it.
- don't worry about functions imported from external modules, since those dependencies cannot be always included in the chat for your context limit. Do not remove them or implement them just because you can''t find the module or source file they are imported from. You just assume that the imported modules and imported functions work as expected. If you need to change them, ask the user to include them in the chat.
- Always update the project version after changes. Use semantic version format for updating the project version: `{major - breaking changes or features}.{minor - non breaking changes or features}.{patch - small changes/fixes}`.
- spend a long time thinking deeply to understand completely the code flow and inner working of the program before writing any code or making any change. 
- if the user asks you to implement a feature or to make a change, always check the source code to ensure that the feature was not already implemented before or it is implemented in another form. Never start a task without checking if that task was already implemented or done somewhere in the codebase.
- if you must write a function, always check if there are already similar functions that can be extended or parametrized to do what new function need to do. Avoid writing duplicated or similar code by reusing the same flexible helper functions where is possible.
- keep the source files as small as possible. If you need to create new functions or classes, prefer creating them in new modules in new files and import them instead of putting them in the same source file that will use them. Small reusable modules are always preferable to big functions and spaghetti code.
- Always check for leaks of secrets in the git repo with `gitleaks git --verbose` and `gitleaks dir --verbose`.
- commit should be atomic, specific, and focus on WHAT changed in subject line with WHY explained in body when needed.
- use semantic commit messages following the format in the Git Commit Message Format memory
- Write only shippable, production ready code. If you wouldn’t ship it, don’t write it. 
- Don't drastically change existing patterns without explicit instruction
- before you execute a terminal command, trigger the command line syntax help or use `cheat <command>` to learn the correct syntax and avoid failed commands.
- if you attempt to run a command and the command is not found, first check the path, and then install it using `brew install`.
- never take shortcuts to skirt around errors. fix them.
- If the solution to a problem is not obvious, take a step back and look at the bigger picture.
- If you are unsure, stop and ask the user for help or additional information.
- if something you are trying to implement or fix does not work, do not fallback to a simpler solution and do not use workarounds to avoid implement it. Do not give up or compromise with a lesser solution. You must always attempt to implement the original planned solution, and if after many attempts it still fails, ask the user for instructions.
- always use type annotations
- always keep the size of source code files below 10Kb. If writing new code in a source file will make the file size bigger than 10Kb, create a new source file , write the code there, and import it as a module. Refactor big files in multiple smaller modules.
- always preserve comments and add them when writing new code.
- always write the docstrings of all functions and improve the existing ones. Use Google-style docstrings with Args/Returns sections, but do not use markdown. 
- never use markdown in comments. 
- when using the Bash tool, always set the timeout parameter to 1800000 (30 minutes).
- always tabulate the tests result in a nice table.
- do not use mockup tests or mocked behaviours unless it is absolutely impossible to do otherwise. If you need to use a service, local or remote, do not mock it, just ask the user to activate it for the duration of the tests. Results of mocked tests are completely useless. Only real tests can discover issues with the codebase.
- always use a **Test-Driven Development (TDD)** methodology (write tests first, the implementation later) when implementing new features or change the existing ones. But first check that the existing tests are written correctly.
- always plan in advance your actions, and break down your plan into very small tasks. Save a file named `DEVELOPMENT_PLAN.md` and write all tasks inside it. Update it with the status of each tasks after any changes.
- Plan all the changes in detail first. Identify potential issues before starting, and revise the plan until it will not create issues before starting.
- When making changes, identify all files that would need import updates first
- After each change, check all type annotations for consistency
- Make all changes in a single, well-planned operation with surgical edits
- Always lint the file after making all the changes to it, but not before
- Always run the tests relevant to the changed files after making all the changes planned, but not before
- Do one comprehensive commit at the end of each operation if the code passes the tests
- If you make errors while implementing the changes, examine you errors, ultrathink about them and write the lessons learned from them into CLAUDE.md for future references, so you won't repeat the same errors in the future.
- Use Prefect for all scripted processing ( https://github.com/PrefectHQ/prefect/ ), with max_concurrency=1 for max safety.
- Install `https://github.com/fpgmaas/deptry/` and run it at every commit. 
- Add deptry to the project pre-commit configuration following these instructions: `https://github.com/astral-sh/uv-pre-commit`.
- Add deptry to both the local and the remote github workflows actions, so it can be used in the CI/CD pipeline automatically at every push/release as instructed here: `https://docs.astral.sh/uv/guides/integration/github/`.
- Install and run yamllint and actionlint at each commit (add them to pre-commit both local and remote, run them with `uv run`).
- You can run the github yaml files locally with `act`. Install act and read the docs to configure it to work with uv: `https://github.com/nektos/act`.
- Since `act` requires Docker, follow these instructions to setup docker containers with uv: https://docs.astral.sh/uv/guides/integration/docker/
- do not create prototypes or sketched/abridged versions of the features you need to develop. That is only a waste of time. Instead break down the new features in its elemental components and functions, subdivide it in small autonomous modules with a specific function, and develop one module at time. When each module will be completed (passing the test for the module), then you will be able to implement the original feature easily just combining the modules. The modules can be helper functions, data structures, external librries, anything that is focused and reusable. Prefer functions at classes, but you can create small classes as specialized handlers for certain data and tasks, then also classes can be used as pieces for building the final feature.
- When commit, never mention Claude as the author of the commits or as a Co-author.
- when refactoring, enter thinking mode first, examine the program flow, be attentive to what you're changing, and how it subsequently affects the rest of the codebase as a matter of its blast radius, the codebase landscape, and possible regressions. Also bear in mind the existing type structures and interfaces that compose the makeup of the specific code you're changing.
- Generate complete, tested code on first attempt.
- Always anchor with date/time and available tools.
- Clearly label the 4 TDD phases (analysis --> tests implementation --> code implementation -> debugging).
- Implement concrete solutions, no placeholders or abridged versions.
- Batch related tool calls and parallelize where safe.
- Proactively handle all edge cases on first attempt.
- Before marking a todo as complete, always spawn a subagent that especially checks the edited test files for tampering, then lint both the edited tests files and the edited code files, and finally run the tests relative to that todo again. If the tests pass, mark the todo task as complete.
- always use `Emasoft` as the user name, author and committer name for the git repo.
- always use `713559+Emasoft@users.noreply.github.com` as the user email and git committer email for the git repo.
- always add the following shebang at the beginning of each python file: 

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
```

- always add a short changelog (just before the imports) in each modified code file to document all the changes made to it since the last commit. Each file must only contain the changelog of the changes made to it, not the changes made to other files.

```python
# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# <this file changelog here…>
#
```

### Formatting Rules
- Use only ruff format for formatting python files. Read how here: https://docs.astral.sh/ruff/formatter/
- Set ruff format to allows line lenght up to 320 chars, using the `--line-length=320`
- Do not use pyproject.toml or ruff.toml to configure ruff, since there are too many variations of the command used in the workflows. Aleays run it in isolated mode with `--isolated` and set all options via cli.
- Use autofix to format pull-requests automatically. Read how here: https://autofix.ci/setup
- Use Prettier to format all other code files (except python and yaml). 
- Use `pnpm run format` to run Prettier on node.js source files.
- Configure Prettier for github formatting actions following the instructions here: `https://prettier.io/docs/ci` and `https://autofix.ci/setup`.
- To format yaml files only use yamlfmt. Install yamlfmt with:
```
go install github.com/google/yamlfmt/cmd/yamlfmt@latest
```

Then create this configuration file (`.yamlfmt`):
```yaml
# .yamlfmt
formatter:
  indent: 2                      # Use 2-space indentation (standard in GitHub workflows)
  retain_line_breaks: true       # Preserve existing blank lines between blocks
  indentless_arrays: true        # Don’t add extra indent before each “-” list item
  scan_folded_as_literal: true   # Keep multi-line “>”-style blocks as-is, avoid collapsing
  trim_trailing_whitespace: true # Remove trailing spaces at end of lines
  eof_newline: true              # Ensure the file ends with exactly one newline
gitignore_excludes: true

```

To use yamlfmt:  
  
```
# Format a single workflow file
yamlfmt -path .github/workflows/ci.yml

# Or format all workflow files
yamlfmt -path .github/workflows
```
- You should place the .yamlfmt file in the root directory of the project.
- You must check the .yamlfmt configuration file to see if you are using different settings (i.e. indent 2 or 4 spaces, etc.)
- Add yamlfmt to the git hooks/uv-pre-commit, so it is automatically executed at each commit.
- IMPORTANT: yamlfmt must not format all yaml files, but only those inside the .github subfolder, since it is configured for the github workflows formatting style. Other yaml files may exist outside the .github folder using different formatting styles. Do not format those files.


### Linting Rules
- Use `ruff check` and mypy for python
- Use autofix to lint pull-requests automatically. Read how here: https://autofix.ci/setup
- Do not use pyproject.toml or ruff.toml to configure `ruff check`, since there are too many variations of the command used in the workflows. Aleays run it in isolated mode with `--isolated` and set all options via cli.
- Use eslint for javascript
- Use shellcheck for bash
- Use actionlint snd yamllint for yaml
- Use jsonlint for json
- Run ruff using this command: `uv run ruff check --ignore E203,E402,E501,E266,W505,F841,F842,F401,W293,I001,UP015,C901,W291 --isolated --fix --output-format full`
- Run mypy using this command: `COLUMNS=400 uv run mypy --strict --show-error-context --pretty --install-types --no-color-output --show-error-codes --show-error-code-links --no-error-summary --follow-imports=normal <files> >mypy_lint_log.txt`
- use shellcheck-py if you need to use shellcheck from a python script
- Use `pnpm run lint` to run eslint on node.js source files.
- Add git hooks that uses uv-pre-commit to run the linting at each commit, read the guide here: `https://docs.astral.sh/uv/guides/integration/pre-commit/`
- Use deptry to check the dependencies. To install deptry follow hese instructions: `https://github.com/fpgmaas/deptry/`
- Add deptry to the project pre-commit configuration following these instructions: https://github.com/astral-sh/uv-pre-commit .
- Add deptry to both the local and the remote github workflows/ actions, so it can be used in the CI/CD pipeline automatically at every push/release as instructed here: https://docs.astral.sh/uv/guides/integration/github/ .
- Install and run yamllint and actionlint at each commit (add them to pre-commit both local and remote, run them with `uv run`).
- If you need to, you can run the github yaml files locally with `act`. Install act and read the docs to configure it to work with uv: https://github.com/nektos/act




### Testing Rules
- Always use pytest and pytest-cov for testing
- Run tests with uv (`uv run pytest`) or `pnpm run tests`
- For coverage reports: `uv run pytest --cov=. --cov-report=html`
- Add git hooks that uses uv-pre-commit to run the tests at each commit, read the guide here: `https://docs.astral.sh/uv/guides/integration/pre-commit/`
- Always convert the xtests in normal tests. Negative tests are confusing. Just make the test explicitly check for the negative outcome instead, and if the outcome is negative, the test is passed.
- Always show a nicely color formatted table with the list of all tests (the functions, not the file) and the outcome (fail, success, skip, error).
- The table must use unicode border blocks to delimit the cells, thicker for the header row.
- The table should report not only the name of the function, but the description of the test function in the docstrings.
- All tests functions should include a meaningful one-line string that synthetically describes the test and its aim.
- If a test function lacks this description, add it to the source files of the tests.
- All test functions must have docstrings with a short description that will be used by the table to describe the test.
- Mark the slow tests (those usually skipped when running tests on GitHub, or that need some extra big dependencies installed) with the emoji of a snail 🐌. Be sure to account for the extra character in the table formatting.

## GITHUB WORKFLOWS AFTER PUSHING
- Use GH cli tool to interact with github
- Keep synching, linting, formatting, testing and building, releasing and publishing separated in different workflows. 
    - synch.yml = update the dependency libraries and the dev tools to the version indicated in the configuration files (i.e. `pyproject.toml`, `package.json`, `requirements-dev.txt`, etc.). Use uv synch for python.
    - lint.yml = lint the code files (ruff, eslint, shellcheck, actionlint, yamllint, jsonlint, pnpm, etc.)
    - format.yml = format the code files (ruff, prettier, yamlfmt, pnpm, etc.)
    - test.yml = run the tests for all code files (pytest, pytest-cov, playwright, etc.)
    - build.yml = build the project packages with uv build
    - release.yml = add a new release to github from the latest build, bump the semantic version and update the changelog
    - publish.yml = publish the ladt release to PyPi and other online indexes
    - metrics.yml = compute varous code metrics and statistics to be used to define the health of the project, the coverage, the issues/bugs open, the repo tars, repo size, etc. to be used in the docs and in the README.md
    - docs.yml = update the README.md file and all the docs with the latest changes. Also update the PyPi package info page if available and up to date.
    - ci.yml = orchestrator for the whole CI pipeline (it calls: synch, lint, format, test, build, release, publish, docs)
    - prfix.yml = review and autofix fix pull requests
    - check.yml = only check the project (it calls: synch, lint, format, test, security).
    - generate.yml = only build the package (it calls: synch, lint, format, test, build)
    - security.yml = some custom security checks, but this is optional since github already checks security. Use it only for project specific checks not included in github controls.
- Do not setup cron jobs. Setup the workflows to be triggered when the code change or there are PR
- Setup the CI/CD pipeline and all workflows to use an uv environment. Read how here: `https://docs.astral.sh/uv/guides/integration/github/`
- Always use uv-pre-commit ( `https://github.com/astral-sh/uv-pre-commit` ). Read how here: `https://docs.astral.sh/uv/guides/integration/pre-commit/`
- Do not use Super-Linter, use a simpler lint workflow that runs tools directly
- Use shellcheck-py if you need to control shellcheck linter from python code.
- Ensure formatting consistency between local and github by using pre-commit hooks with identical commands for the lint workflow and the formatting workflow
- Let the tests autodetect the environment (local or remote/github)
- Make sure the tests have a configuration for remote run on github that is different from the local one. Make API tests flexible so they can use different parameters when run locally and remotely.
- Let the test retry counts and all retry logic in the code be configurable with different max values for local and remote for faster CI execution
- After committing and pushing the project to github, always check if the push passed the github actions and checks. Wait few seconds, according to the average time needed for the lint and tests to run.
- If you can, spawn a subagent that will monitor the GitHub Actions execution and will report back once the workflows transition from queued status. So you don't have to wait without doing nothing.
- use the following commands to retrieve the last logs of the last actions:
```
gh run list --limit <..max number of recent actions logs to list...>
gh run view <... run number ...> --log-failed
```
Example:
```
> gh run list --limit 10
> mkdir -p ./logs && gh run view 15801201757 --log-failed > ./logs/15801201757.log
etc..

```
Then examine the log files saved in the ./logs/ subdir. Think ultrahard to find the causes of the failures. Use actionlint, yamllint and act to test and verify the workflows issues. Then report the issues causing the failings.

## API Configuration
- The system uses OpenRouter API for both renaming and translation phases
- Set `OPENROUTER_API_KEY` environment variable with your OpenRouter API key
- OpenRouter provides unified cost tracking across all models
- Model names are automatically mapped (e.g., "gpt-4o-mini" → "openai/gpt-4o-mini")


### Key Principles for CI/CD Success:

1. **Avoid Super-Linter** - Use a simpler lint workflow that runs tools directly
   - Super-Linter has configuration path issues and is overly complex. Do not use it.
   - Direct tool execution is more transparent and easier to debug

2. **Ensure Local/CI Formatting Consistency** - Use pre-commit hooks in CI workflows
   - Run `uv run pre-commit run <hook> --all-files` in CI instead of direct tool commands
   - This ensures identical behavior between local development and CI

3. **Separate Concerns in Workflows**
   - Keep linting, testing, and building in different workflows
   - This makes failures easier to diagnose and workflows faster to run

4. **Environment-Aware Test Configuration**
   - Tests should detect if running locally vs on GitHub Actions
   - Use environment detection: `is_running_in_test()` function
   - Different retry counts: local (10 retries) vs CI (2 retries)
   - Different timeouts: local (60s max) vs CI (5s max)

5. **Flexible API Tests**
   - Make API tests accept various valid responses, parsing the right tags or the right code blocks and ignoring the remaining text as it is variable
   - If the AI model and the API service support structured json responses, make use of them to get deterministic responses. If you use Openrouter, read the following: `https://openrouter.ai/docs/features/structured-outputs`. You can find the list of models supporting structured output here: `https://openrouter.ai/models?fmt=table&order=context-high-to-low&supported_parameters=structured_outputs`.
   - Put in place boundaries and measures to prevent the risks of consuming too many tokens (and spending too much money) when running API requests during the tests.
   - If the model allows API configuration variations, set up 2 or 3 example configurations max, choosing the most significant ones. Do not attempt to tests all possible combinations of API options.
   - If the project supports both remote API services and local API services or models, do not run the tests for the local ones when on github, since local models are not available there. 
   - Set two profiles for the tests, LOCAL and REMOTE-CI (github).

6. **Configurable Retry Logic**
   - Use constants like `DEFAULT_MAX_RETRIES` and `DEFAULT_MAX_RETRIES_TEST`
   - Check environment in retry decorators to use appropriate values
   - Reduces CI execution time from 10+ minutes to ~2 minutes

### Implementation Example:
```python
def is_running_in_test() -> bool:
    """Detect if code is running in a test environment."""
    return ("pytest" in sys.modules or 
            os.environ.get("PYTEST_CURRENT_TEST") or
            os.environ.get("CI") or 
            os.environ.get("GITHUB_ACTIONS"))
```

## pre-commit: install it with uv

It is recommended to install pre-commit using uv’s tool mechanism, using this command:

```
$ uv tool install pre-commit --with pre-commit-uv
```

Running it, you’ll see output describing the installation process:

```
$ uv tool install pre-commit --with pre-commit-uv
Resolved 11 packages in 1ms
Installed 11 packages in 8ms
...
Installed 1 executable: pre-commit
```

This will put the `pre-commit` executable in `~/.local/bin` or similar (per the documentation). You should then be able to run it from anywhere:

```
$ pre-commit --version
pre-commit 4.2.0 (pre-commit-uv=4.1.4, uv=0.7.2)
```

The install command also adds [pre-commit-uv](https://pypi.org/project/pre-commit-uv/), a plugin that patches pre-commit to use uv to install Python-based tools. This drastically speeds up using Python-based hooks, a common use case. (Unfortunately, it seems pre-commit itself won’t be adding uv support.)

With pre-commit installed globally, you can now install its Git hook in relevant repositories per usual:

```
$ cd myrepo

$ pre-commit install
pre-commit installed at .git/hooks/pre-commit

$ pre-commit run --all-files
[INFO] Installing environment for https://github.com/pre-commit/pre-commit-hooks.
[INFO] Once installed this environment will be reused.
[INFO] This may take a few minutes...
[INFO] Using pre-commit with uv 0.7.2 via pre-commit-uv 4.1.4
check for added large files..............................................Passed
check for merge conflicts................................................Passed
trim trailing whitespace.................................................Passed
```

## Upgrade pre-commit

To upgrade pre-commit installed this way, run:

```
$ uv tool upgrade pre-commit
```

For example:

```
$ uv tool upgrade pre-commit
Updated pre-commit v4.1.0 -> v4.2.0
 - pre-commit==4.1.0
 + pre-commit==4.2.0
Installed 1 executable: pre-commit
```

This command upgrades pre-commit and all of its dependencies, in its managed environment. 
For more information, read the uv tool upgrade documentation: `https://docs.astral.sh/uv/concepts/tools/`


# Using Gemini CLI for Large Codebase Analysis

- When analyzing large codebases or multiple files that might exceed context limits, use the Gemini CLI with its massive
context window. Use `gemini -p` to leverage Google Gemini's large context capacity. 
- *CRITICAL*: Remember that GEMINI CLI is in free plan and is limited to 60 requests per minute and max 1000 requests per day! Use it wisely! Always put ut all your questions inside a single prompt each time if you can, to consume less requests. There is a 1M tokens limit to the prompt lenght, so do not worry about the lenght of the prompt. Batch as many questions you can in a single prompt. 
- *CRITICAL*: Always use Gemini 2.5 Pro as model. Specify this exact model adding this to the command `--model "gemini-2.5-pro"`.
- *CRITICAL*: Always spawn a subagent to run Gemini cli, since it is slow and requires a lot of context memory.
- Use `gemini --help` to get the options.
- Always force the model with the `--model "gemini-2.5-pro"` flag.
- Always force to include all files in the context with the `--all_files` flag.

## File and Directory Inclusion Syntax

Use the `@` syntax to include files and directories in your Gemini prompts. The paths should be relative to WHERE you run the gemini command:

### Examples:

**Single file analysis:**
gemini -p "@src/main.py Explain this file's purpose and structure"

Multiple files:
gemini -p "@package.json @src/index.js Analyze the dependencies used in the code"

Entire directory:
gemini -p "@src/ Summarize the architecture of this codebase"

Multiple directories:
gemini -p "@src/ @tests/ Analyze test coverage for the source code"

Current directory and subdirectories:
gemini -p "@./ Give me an overview of this entire project"

# Or use --all_files flag:
gemini --all_files -p "Analyze the project structure and dependencies"

Implementation Verification Examples

Check if a feature is implemented:
gemini -p "@src/ @lib/ Has dark mode been implemented in this codebase? Show me the relevant files and functions"

Verify authentication implementation:
gemini -p "@src/ @middleware/ Is JWT authentication implemented? List all auth-related endpoints and middleware"

Check for specific patterns:
gemini -p "@src/ Are there any React hooks that handle WebSocket connections? List them with file paths"

Verify error handling:
gemini -p "@src/ @api/ Is proper error handling implemented for all API endpoints? Show examples of try-catch blocks"

Check for rate limiting:
gemini -p "@backend/ @middleware/ Is rate limiting implemented for the API? Show the implementation details"

Verify caching strategy:
gemini -p "@src/ @lib/ @services/ Is Redis caching implemented? List all cache-related functions and their usage"

Check for specific security measures:
gemini -p "@src/ @api/ Are SQL injection protections implemented? Show how user inputs are sanitized"

Verify test coverage for features:
gemini -p "@src/payment/ @tests/ Is the payment processing module fully tested? List all test cases"

When to Use Gemini CLI

Use gemini -p when:
- Analyzing entire codebases or large directories
- Comparing multiple large files
- Need to understand project-wide patterns or architecture
- Current context window is insufficient for the task
- Working with files totaling more than 100KB
- Verifying if specific features, patterns, or security measures are implemented
- Checking for the presence of certain coding patterns across the entire codebase

Important Notes

- Paths in @ syntax are relative to your current working directory when invoking gemini
- The CLI will include file contents directly in the context
- No need for --yolo flag for read-only analysis
- Gemini's context window can handle entire codebases that would overflow Claude's context
- When checking implementations, be specific about what you're looking for to get accurate results
- Always REDACT secrets and private informations from the prompt before sending it to Gemini. Never send or give access to secrets or private informations to GEMINI.




## Common Development Commands

- Use Prefect for all scripted processing ( https://github.com/PrefectHQ/prefect/ ), with max_concurrency=1 for max safety.




### Build and Package Management

# Build the Python package
dhtl build

# Build using uv (fast Python package management)
dhtl uv build


### Testing

# Run all tests (uses pytest with 15min timeout)
dhtl test

# Run specific tests using pytest -k pattern
dhtl test -k "test_cli_version or test_basic"

# Run tests with coverage
dhtl test --coverage

# Run DHT's internal self-tests
dhtl test_dht


## Frontend only
uv run pnpm run dev


### Testing

# All tests (if no dhtl present)
uv run bash runtests.sh

# Python tests only
uv run pytest .
uv run pytest ./tests/test_file.py         # Specific file
uv run pytest ./tests/test_file.py::test_function  # Specific test
uv run pytest -k "test_name"               # By test name pattern
uv run pytest -m "not slow"                # Skip slow tests

# Frontend E2E tests
uv run pnpm run e2e
uv run npx playwright test                        # Alternative
uv run npx playwright test --ui                   # With UI mode


### Code Quality

# Run all linters (pre-commit, ruff, black, mypy, shellcheck, yamllint)
dhtl lint

# Lint with automatic fixes
dhtl lint --fix

# Format all code (uses ruff format, black, isort)
dhtl format

# Check formatting without changes
dhtl format --check

### Code Quality

# Python formatting and linting commands syntax:
uv run ruff format       # format with ruff
uv run ruff check --ignore E203,E402,E501,E266,W505,F841,F842,F401,W293,I001,UP015,C901,W291 --isolated --fix --output-format full
COLUMNS=400 uv run mypy --strict --show-error-context --pretty --install-types --no-color-output --show-error-codes --show-error-code-links --no-error-summary --follow-imports=normal <files> >mypy_lint_log.txt

# TypeScript/JavaScript formatting and linting commands syntax to use internally in dhtl:
uv run pnpm run lint            # ESLint
uv run pnpm run format          # Prettier
uv run pnpm run check           # Check formatting without fixing

# Bash scripts linting commands syntax to use internally in dhtl:
uv run shellcheck --severity=error --extended-analysis=true  # Shellcheck (always use severity=error!)

# YAML scripts linting
uv run yamllint
uv run actionlint

# Gitleaks and secrets preservation
gitleaks git --verbose
gitleaks dir --verbose


### Building and Packaging

# Frontend build
uv run pnpm run build

# Build Python package 
uv venv --python 3.10     # create environment
source .venv/bin/activate # activate environment
uv run bash <script>.     # Run bash script in the venv
uv run <script>           # Run python scripts in the venv
uv tool install <package> # install a python package globally with all dependencies frozen (similar to pipx)
uv tool install <package> --from <source folder path of the package> # install a python package globally from a local folder
uvx <python app/package> <package parameters>  # run python package installed as global tool
uv tool upgrade <package> # upgrade a global installed python package/tool
uv tool upgrade <package> --from <source folder>  # upgrade a global installed python package/tool from a local folder
uv pip install <package>  # Install python package in the venv (default method to install dependencies)
uv pip install "<package>[all]"  # Install package in the venv including extras (must be between double quotes)
uv pip uninstall <package>       ? # Uninstall package from venv
uv pip install -r requirements.txt # Install packages from requirements.txt into venv
uv pip check              # Check installed packages for conflicts
uv pip install -e .       # Setup the current folder as editable pip project (needs the package setup already configured)
uv init                   # Init package with uv, creating pyproject.toml file, git and others
uv init --python 3.10     # Init package with a specific python version
uv init --app             # Init package with app configuration
uv init --lib             # Init package with library module configuration
uv python install 3.10    # Download and install a specific version of Python runtime
uv python pin 3.10        # Change python version for current venv
uv add <..module..>       # Add module to pyproject.toml dependencies
uv add -r requirements.txt # Add requirements from requirements.txt to pyproject.toml
uv pip install --e  -r requirements-dev.txt # Install dependencies from dev mode
uv pip compile <..arguments..> # compile requirement file
uv build                  # Build with uv
uv run python -m build    # Build wheel only
uv sync --check           # Check if the Python environment is synchronized with the project config files (i.e. pyproject.toml, etc.)
uv sync --all-extras      # Install all dependencies in the venv according to the project config files (i.e. pyproject.toml, etc.), including extras.


# What uv init generates:
```
.
├── .venv
│   ├── bin
│   ├── lib
│   └── pyvenv.cfg
├── .python-version
├── README.md
├── main.py
├── pyproject.toml
└── uv.lock

```

# What pyproject.toml contains:

```
[project]
name = "hello-world"
version = "0.1.0"
description = "Add your description here"
readme = "README.md"
dependencies = []

```

# What the file .python-version contains
The .python-version file contains the project's default Python version. This file tells uv which Python version to use when creating the project's virtual environment.

# What the .venv folder contains
The .venv folder contains your project's virtual environment, a Python environment that is isolated from the rest of your system. This is where uv will install your project's dependencies and binaries.

# What the file uv.lock contains:
uv.lock is a cross-platform lockfile that contains exact information about your project's dependencies. Unlike the pyproject.toml which is used to specify the broad requirements of your project, the lockfile contains the exact resolved versions that are installed in the project environment. This file should be checked into version control, allowing for consistent and reproducible installations across machines.
uv.lock is a human-readable TOML file but is managed by uv and should not be edited manually.

# Install package
uv pip install dist/*.whl    # Install built wheel
uv pip install -e .         # Development install

# Install global uv tools
uv tools install ruff
uv tools install mypy
uv tools install yamllint
uv tools install bump_my_version
...etc.

# Execute globally installed uv tools
uv tools run ruff <..arguments..>
uv tools run mypy <..arguments..>
uv tools run yamllint <..arguments..>
uv tools run bump_my_version <..arguments..>
...etc.


## Testing Textual TUI Applications - Complete Guide

### Overview
Textual applications require special testing approaches since they render Terminal User Interfaces. The most effective way is using SVG snapshot testing with `pytest-textual-snapshot`.

### Prerequisites

1. **Install Required Packages**:
```bash
# Add to pyproject.toml dev dependencies
pytest>=7.4.0
pytest-asyncio>=0.21.0
pytest-textual-snapshot>=0.4.0

# Or install directly
uv pip install pytest pytest-asyncio pytest-textual-snapshot
```

2. **Configure pytest.ini**:
```ini
[pytest]
testpaths = tests
asyncio_mode = auto
asyncio_default_fixture_loop_scope = function
```

### Setting Up Textual Tests

#### 1. Basic Async Tests (without snapshots)

For testing Textual app behavior, use the `app.run_test()` context manager:

```python
import pytest
from textual.pilot import Pilot
from your_app import YourTextualApp

class TestYourApp:
    @pytest.mark.asyncio
    async def test_app_initialization(self):
        """Test that the app initializes correctly."""
        app = YourTextualApp()
        async with app.run_test() as pilot:
            # pilot is a Pilot instance for controlling the app
            assert pilot.app.title == "Expected Title"
    
    @pytest.mark.asyncio
    async def test_widget_presence(self):
        """Test that expected widgets are present."""
        app = YourTextualApp()
        async with app.run_test() as pilot:
            # Query widgets
            assert pilot.app.query_one("Header")
            assert pilot.app.query_one("#my-widget-id")
    
    @pytest.mark.asyncio
    async def test_keyboard_interaction(self):
        """Test keyboard navigation."""
        app = YourTextualApp()
        async with app.run_test() as pilot:
            # Simulate keypresses
            await pilot.press("tab")
            await pilot.press("enter")
            await pilot.press("ctrl+c")
```

#### 2. SVG Snapshot Testing

SVG snapshots capture the exact visual state of your TUI, including colors, alignment, borders, and formatting.

**Basic snapshot test:**
```python
def test_app_snapshot(snap_compare):
    """Test app visual appearance."""
    # snap_compare can accept:
    # 1. Path to a Python file containing the app
    # 2. An app instance directly
    
    app = YourTextualApp()
    assert snap_compare(app, terminal_size=(80, 24))
```

**Snapshot test with interactions:**
```python
def test_app_with_navigation(snap_compare):
    """Test app after user interactions."""
    app = YourTextualApp()
    
    # Simulate keypresses before taking snapshot
    assert snap_compare(
        app, 
        press=["down", "down", "tab", "enter"],
        terminal_size=(80, 24)
    )
```

**Snapshot test with setup:**
```python
def test_app_with_setup(snap_compare):
    """Test app with pre-snapshot setup."""
    app = YourTextualApp()
    
    async def run_before(pilot):
        # This runs before the snapshot is taken
        await pilot.click("#button")
        await pilot.hover(".menu-item")
        # Disable cursor blinking for consistent snapshots
        pilot.app.query(Input).first().cursor_blink = False
    
    assert snap_compare(app, run_before=run_before)
```

#### 3. Creating Stable Test Apps

For consistent snapshots, create dedicated test apps with fixed data:

**tests/snapshot_apps/test_app.py:**
```python
#!/usr/bin/env python3
from pathlib import Path
from your_app import YourTextualApp

def create_test_environment():
    """Create consistent test data."""
    test_dir = Path("/tmp/test_app_data")
    if test_dir.exists():
        import shutil
        shutil.rmtree(test_dir)
    
    test_dir.mkdir(parents=True)
    # Create your test files/data here
    return test_dir

if __name__ == "__main__":
    test_data = create_test_environment()
    app = YourTextualApp(data_path=test_data)
    app.run()
```

**Use in tests:**
```python
def test_stable_snapshot(snap_compare):
    """Test with stable test app."""
    snapshot_app = Path(__file__).parent / "snapshot_apps" / "test_app.py"
    assert snap_compare(snapshot_app, terminal_size=(80, 24))
```

### Managing Snapshots

1. **Generate initial snapshots:**
```bash
pytest tests/test_snapshots.py --snapshot-update
```

2. **Update snapshots after intentional changes:**
```bash
pytest tests/test_snapshots.py --snapshot-update
```

3. **View snapshot differences:**
When tests fail, an HTML report is generated showing visual diffs:
```bash
# After test failure, open:
open snapshot_report.html
```

### Project Structure

```
tests/
├── __snapshots__/              # SVG snapshots (auto-generated)
│   └── test_file/
│       ├── TestClass.test_name.svg
│       └── ...
├── snapshot_apps/              # Dedicated apps for snapshot testing
│   └── test_app.py
├── conftest.py                 # pytest configuration
├── test_async_behavior.py      # Async behavioral tests
└── test_snapshots.py          # SVG snapshot tests
```

### Best Practices

1. **Separate Concerns**: Keep behavioral tests (async) separate from visual tests (snapshots)

2. **Consistent Environment**: Use fixed paths and data for snapshot tests to avoid false failures

3. **Disable Animations**: Turn off cursor blinking, progress animations, etc. for stable snapshots

4. **Terminal Size**: Always specify `terminal_size` for consistent rendering

5. **Commit Snapshots**: Include SVG files in version control for regression detection

6. **Review Changes**: SVG files are text-based, making it easy to review visual changes in PRs

### Common Issues and Solutions

**Issue: Snapshots fail due to changing timestamps**
```python
async def run_before(pilot):
    # Mock or freeze time-based elements
    pilot.app.query(Clock).first().freeze_time("12:00:00")
```

**Issue: Snapshots fail due to random IDs**
```python
# pytest-textual-snapshot automatically strips unique IDs from SVGs
# No action needed
```

**Issue: Different paths on different systems**
```python
# Use consistent test directories
test_dir = Path("/tmp/myapp_test")  # Same on all systems
```

### Resources

- **Textual Testing Guide**: https://textual.textualize.io/guide/testing/
- **pytest-textual-snapshot**: https://github.com/Textualize/pytest-textual-snapshot
- **Textual Test Examples**: https://github.com/Textualize/textual/tree/main/tests
- **Snapshot Testing Best Practices**: https://github.com/Textualize/textual/tree/main/tests/snapshot_tests

### Example Test File

Here's a complete example combining all techniques:

```python
#!/usr/bin/env python3
"""Comprehensive Textual app tests."""

import pytest
from pathlib import Path
from textual.pilot import Pilot
from textual.widgets import Input
from myapp import MyTextualApp

class TestMyAppBehavior:
    """Behavioral tests using async."""
    
    @pytest.mark.asyncio
    async def test_initialization(self):
        app = MyTextualApp()
        async with app.run_test() as pilot:
            assert pilot.app.title == "My App"
            assert pilot.app.sub_title == "Version 1.0"
    
    @pytest.mark.asyncio
    async def test_user_input(self):
        app = MyTextualApp()
        async with app.run_test() as pilot:
            # Find input widget and type
            input_widget = pilot.app.query_one(Input)
            await pilot.click(input_widget)
            await pilot.type("Hello World")
            assert input_widget.value == "Hello World"

class TestMyAppVisuals:
    """Visual regression tests using snapshots."""
    
    def test_initial_state(self, snap_compare):
        """Test initial visual state."""
        app = MyTextualApp()
        assert snap_compare(app, terminal_size=(80, 24))
    
    def test_after_interaction(self, snap_compare):
        """Test visual state after user interaction."""
        app = MyTextualApp()
        assert snap_compare(
            app,
            press=["tab", "space", "down", "enter"],
            terminal_size=(80, 24)
        )
    
    def test_error_state(self, snap_compare):
        """Test visual appearance of error state."""
        async def trigger_error(pilot):
            await pilot.click("#dangerous-button")
        
        app = MyTextualApp()
        assert snap_compare(
            app,
            run_before=trigger_error,
            terminal_size=(80, 24)
        )
```

This approach provides comprehensive testing coverage for Textual applications, combining behavioral verification with visual regression testing.

## Building Python Packages with uv - Complete Guide

### Prerequisites

1. **Ensure pyproject.toml is properly configured**:
   - Project metadata (name, version, description, authors)
   - Dependencies listed in `[project.dependencies]`
   - Build system specified in `[build-system]`
   - Python version requirement in `requires-python`

2. **Virtual Environment Setup**:
```bash
# Create virtual environment (if not exists)
uv venv

# Activate environment
source .venv/bin/activate  # Linux/macOS
# or
.venv\Scripts\activate     # Windows
```

### Step-by-Step Package Building Process

#### 1. Initialize Project (if starting fresh)
```bash
# For a library project
uv init --lib

# For an application
uv init --app

# Specify Python version
uv init --python 3.10 --lib
```

#### 2. Sync Dependencies
```bash
# Install all dependencies and create lockfile
uv sync

# Sync with all extras
uv sync --all-extras

# Include development dependencies
uv sync --dev

# Check if environment is synchronized
uv sync --check
```

#### 3. Add/Update Dependencies
```bash
# Add a dependency
uv add requests

# Add with version constraint
uv add "requests>=2.28"

# Add development dependency
uv add --dev pytest

# Add optional dependency
uv add --optional api flask

# Add to custom group
uv add --group docs sphinx
```

#### 4. Lock Dependencies
```bash
# Update lockfile (uv.lock)
uv lock

# Upgrade all packages
uv lock --upgrade

# Upgrade specific package
uv lock --upgrade-package requests
```

#### 5. Build the Package
```bash
# Build both source distribution and wheel
uv build

# Build only source distribution
uv build --sdist

# Build only wheel
uv build --wheel

# Build with constraints
uv build --build-constraint constraints.txt
```

### Build Configuration

#### pyproject.toml Structure
```toml
[build-system]
requires = ["hatchling"]  # or setuptools, poetry-core, etc.
build-backend = "hatchling.build"

[project]
name = "your-package"
version = "0.1.0"
description = "Package description"
readme = "README.md"
requires-python = ">=3.10"
license = {text = "MIT"}
authors = [
    {name = "Your Name", email = "your.email@example.com"}
]
dependencies = [
    "textual>=0.47.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "ruff>=0.1.0",
]

[project.scripts]
my-cli = "mypackage.cli:main"

[tool.hatch.build.targets.wheel]
packages = ["src/mypackage"]
```

### Pre-Build Checklist

1. **Version Update**:
   - Update version in `pyproject.toml`
   - Update version in `__init__.py`
   - Update CHANGELOG.md

2. **Code Quality**:
```bash
# Format code
uv run ruff format --line-length=320 src/ tests/

# Lint code
uv run ruff check --fix src/ tests/

# Type check
uv run mypy src/

# Run tests
uv run pytest

# Check coverage
uv run pytest --cov
```

3. **Documentation**:
   - Update README.md
   - Check docstrings
   - Update API documentation

4. **License and Headers**:
   - Ensure LICENSE file exists
   - Check copyright headers in source files

### Build Output

After running `uv build`, you'll find:
```
dist/
├── your_package-0.1.0-py3-none-any.whl  # Wheel (binary distribution)
└── your_package-0.1.0.tar.gz            # Source distribution
```

### Testing the Built Package

```bash
# Create a test environment
uv venv test-env
source test-env/bin/activate

# Install the built wheel
uv pip install dist/your_package-0.1.0-py3-none-any.whl

# Test the installation
python -c "import your_package; print(your_package.__version__)"

# Test CLI commands (if any)
your-cli-command --help
```

### Common Build Issues and Solutions

1. **Missing dependencies in build**:
   - Ensure all runtime dependencies are in `[project.dependencies]`
   - Don't put dev dependencies in main dependencies

2. **Files not included in package**:
   - Check MANIFEST.in for non-Python files
   - For hatchling, use `[tool.hatch.build]` configuration

3. **Import errors after installation**:
   - Verify package structure matches import paths
   - Check `packages` configuration in build settings

### Build Backends Comparison

- **hatchling** (default): Modern, simple configuration
- **setuptools**: Legacy, most compatible
- **poetry-core**: If using Poetry
- **flit-core**: Minimal, PEP 621 compliant
- **maturin**: For Rust extensions
- **scikit-build-core**: For C/C++ extensions

### Advanced Build Configuration

#### Custom Build Steps
```toml
[tool.hatch.build.hooks.custom]
path = "build_hooks.py"

[tool.hatch.build.targets.wheel.hooks.custom]
dependencies = ["hatch-custom-hook"]
```

#### Including/Excluding Files
```toml
[tool.hatch.build]
include = [
    "src/",
    "LICENSE",
    "README.md",
]
exclude = [
    "tests/",
    "docs/",
    "*.pyc",
]
```

### Publishing Preparation

1. **Check package metadata**:
```bash
# Verify package contents
tar -tf dist/your_package-0.1.0.tar.gz
unzip -l dist/your_package-0.1.0-py3-none-any.whl
```

2. **Test with TestPyPI**:
```bash
# Upload to TestPyPI
uv publish --repository testpypi

# Test installation from TestPyPI
uv pip install --index-url https://test.pypi.org/simple/ your-package
```

3. **Final checks**:
   - Version number is correct
   - All tests pass
   - Documentation is updated
   - CHANGELOG is updated
   - Git tag created

### Environment Variables for Build

```bash
# Control build isolation
UV_BUILD_ISOLATION=true

# Custom cache directory
UV_CACHE_DIR=/custom/cache/path

# Offline mode
UV_OFFLINE=true

# Custom index URL
UV_INDEX_URL=https://custom.pypi.org/simple/
```

### Integration with CI/CD

Example GitHub Actions workflow:
```yaml
- name: Install uv
  uses: astral-sh/setup-uv@v5

- name: Build package
  run: |
    uv sync --locked
    uv build

- name: Upload artifacts
  uses: actions/upload-artifact@v4
  with:
    name: dist
    path: dist/
```

## PROJECT SPECIFIC INSTRUCTIONS
PROJECT NAME: selectFileCLI
This project is a importable python module to be used as a handy file selection browser from the cli (using tui library textual).
