---
name: resolving-dart-defects
description: Use when investigating or fixing bugs, regressions, vulnerabilities, races, leaks, performance defects, or incorrect behavior in any Dart or Flutter project.
---

# Resolving Dart Defects

## Core Rule

Treat the report and its proposed fix as hypotheses. Restore the violated invariant at its
root cause, prove the behavior with a failing check or approved evidence substitute, and
require independent acceptance.

Follow all three stages in order. Time pressure, a small diff, authority, or green existing
tests never removes a stage.

## Roles

| Role | Responsibility |
| --- | --- |
| Primary agent | Investigates, scopes, presents options, obtains approval, and orchestrates the loop |
| `dart-defect-implementer` | Proves the defect first, then implements the approved repair |
| `dart-defect-reviewer` | Independently checks acceptance without editing source files |

The primary agent owns every decision. Explorers may locate files and relationships, but do
not delegate root-cause analysis, scope, or repair selection to them.

## Stage 1: Evidence And Repair Contract

Do not edit production code or tests during this stage.

1. Read repository instructions and determine the actual Dart/Flutter commands, supported
   platforms, generated-code rules, and current worktree state. Preserve unrelated changes.
2. Rewrite the report as a falsifiable claim: observed behavior, expected behavior, inputs,
   environment, and impact. Reproduce it or establish direct static evidence. If neither is
   possible, label it unconfirmed rather than inventing a fix.
3. Trace the causal neighborhood: callers, callees, ownership and lifecycle, sibling paths
   governed by the same invariant, trust boundaries, async or isolate boundaries, and
   platform implementations. Do not turn this into an unrelated whole-repository audit.
4. For security defects, record attacker control, prerequisites, affected assets, impact,
   and the intended fail-open or fail-closed policy. Never test against third-party systems
   without authorization.
5. Produce an **Issue Dossier** containing:
   - original claim and confirmed facts;
   - reproduction or static evidence, including commands and observed output;
   - expected behavior and violated invariant;
   - root cause with confidence and rejected alternatives;
   - causal scope, compatibility risks, and adjacent findings;
   - observable acceptance criteria;
   - two or more viable repair options when they genuinely exist, with tradeoffs and a
     recommendation. Do not manufacture alternatives for a single safe repair.
6. Present the dossier and wait for the user's explicit choice. The original request to fix
   the defect is not approval of a repair option.

Include a proposed substitute in the dossier when an automated RED test is impractical:
a deterministic harness, static proof, instrumented platform reproduction, or bounded stress
check with before/after evidence. State what it cannot prove. It requires explicit approval.

## Stage 2: RED Then Repair

Start a fresh `dart-defect-implementer` with the approved dossier, selected option, acceptance
criteria, repository constraints, allowed scope, and validation commands.

The implementer must:

1. Unless the dossier contains an approved substitute, add the smallest behavior-level
   regression test before production changes.
2. Format only the regression-test files, then run only those tests. Confirm they fail for the
   expected defect. A test that passes or fails for compilation, environment, or setup is not
   RED; correct the test and repeat without editing production code.
3. For an approved substitute, record its exact procedure, environment/build identity, and
   raw pre-repair result before production changes. If the need for a waiver appears now,
   return `BLOCKED` for user approval.
4. Repair the root cause at the owner of the invariant. Keep the existing architecture and
   public behavior unless the approved contract requires a change.
5. Format every Dart file changed by the implementer.
6. Run the repository analyzer once. If it reports a problem, fix it, format changed files,
   and run the analyzer again. Do not continue until it is clean.
7. Run the repository's complete applicable test suite once. Do not run the targeted tests
   again first when the full suite includes them. Tests excluded from the default suite, such
   as integration or platform tests, remain separate required commands.

Run every `dart`, `flutter`, `fvm`, `melos`, build-runner, and analyzer command sequentially.
Never place two toolchain commands in one parallel/multi-tool call, overlap them across agents,
or start the next command before the previous process exits. Use one analyzer interface per
gate; do not run CLI analysis and LSP/MCP analysis for the same gate.

A hung, timed-out, or cancelled command does not pass its gate. Do not start another toolchain
command until the old process has exited. Retry only after identifying and removing a transient
cause such as a startup lock; otherwise return `BLOCKED`. Never switch analyzer interfaces to
bypass a hung or failed gate.

Validation is fail-fast. After any post-repair code change, resume at formatting, then analysis,
then the complete suite. Do not spend time on later gates after an earlier gate fails.

Tests must assert observable behavior, not private implementation details. Never weaken,
delete, skip, or broadly rewrite a test merely to obtain green output.

## Dart Repair Checks

Inspect the concerns relevant to the causal path:

- `Future`, `Stream`, cancellation, missing `await`, late callbacks, races, isolates, and
  deterministic cleanup of subscriptions, controllers, ports, timers, and platform handles;
- null safety, `dynamic`, casts, mutable aliases, collection ownership, and exception scope;
- public API compatibility, package constraints, generated code, platform channels, and
  Android/iOS/web/desktop divergence;
- security validation and authorization at trust boundaries, with no broad catch or silent
  fail-open fallback;
- algorithmic cost and avoidable copies, intermediate collections, closures, or allocations
  in demonstrated hot paths. Do not trade clarity for speculative micro-optimization.

A flag or new state field is valid only when it models necessary state with one owner, a
documented invariant, and complete transitions. Reject shadow state, duplicate sources of
truth, temporal-coupling flags, and state that can desynchronize from the resource it tracks.

## Stage 3: Independent Acceptance

Start a new `dart-defect-reviewer` in a fresh context for every review iteration. Give it the
original report, confirmed facts, reproduction, expected behavior, acceptance criteria,
constraints, changed-file list, validation commands, and RED or approved substitute evidence.
For a substitute, include the explicit waiver, exact procedure and environment, raw pre- and
post-repair results, and stated limitations.

Do **not** give it the selected repair option, patch plan, or implementer's reasoning. The
reviewer first derives its own expected edge, failure, security, and concurrency checks; only
then may it inspect the diff, changed tests, callers, and sibling paths.

If inspection already proves a blocking defect, return `REWORK` without running expensive
commands. Otherwise run these gates sequentially and stop at the first failure:

1. Check formatting of all changed Dart files without modifying them.
2. Run the repository analyzer once.
3. Run the complete applicable test suite once.

Do not run targeted tests before the complete suite when it includes them. Run a test command
separately only when the complete command excludes it or when diagnosing an observed failure.
The same no-parallel toolchain rule from Stage 2 applies to every reviewer command.

The reviewer runs permitted checks and returns exactly one verdict:

- `PASS`: acceptance criteria are proved and no blocking regression or vulnerability remains.
- `REWORK`: each finding includes severity, file/line, evidence, risk, and required behavior
  or test. The reviewer does not patch it.
- `BLOCKED`: evidence, environment, or requirements are insufficient; list what is needed.

Return localized `REWORK` to the same implementer. Use a fresh implementer when the root cause,
repair strategy, or architecture is wrong. After any change, start another fresh reviewer.
Only `PASS` completes the task; the primary agent then reports changes, evidence, commands,
and residual limitations.

## Stop These Shortcuts

| Rationalization | Required response |
| --- | --- |
| "The user already diagnosed it" | Verify the claim and root cause independently |
| "It is a one-line fix" | A small diff still needs RED evidence and review |
| "Existing tests are green" | Existing tests do not reproduce the reported defect |
| "It cannot be tested" | Propose an explicit substitute and obtain approval |
| "A boolean guard is simplest" | Prove ownership, invariant, transitions, and failure recovery |
| "I reviewed my own patch" | Self-review does not replace a fresh reviewer |
| "We have no time" | Reduce scope, never remove evidence or security gates |
| "Targeted tests are faster" | Use them for RED; after repair the complete suite replaces them |

Red flags: production edits before RED or an approved substitute, a test that never failed,
parallel or overlapping toolchain commands, targeted GREEN followed by the same full suite,
broad catches, silent defaults, unexplained force casts, duplicated state, only the reported
caller patched despite a shared cause, unrelated refactoring, hidden command failures, or
completion without `PASS`.
