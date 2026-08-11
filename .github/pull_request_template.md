## Why

<!-- What problem does this PR solve? -->

Closes #

## Quality Gates

- [ ] Independent subagent review completed; blocking findings are resolved.
- [ ] Automated checks completed; include exact commands and outcomes below.
- [ ] Manual validation completed by the implementing agent; include scenarios and outcomes below.

### Automated checks

<!-- Example: git diff --check; swift test; xcodebuild ... build -->

### Manual validation

<!-- Describe device/OS, permissions, inputs, and observed results. -->

### Deferred review findings

<!-- List only approved non-blocking findings with impact, temporary behavior, and Issue link. -->

## Changes

- <!-- Summarize the implementation. -->

## Non-goals

- <!-- State exclusions or write "None". -->

## Verification

- [ ] Debug build succeeds
- [ ] Relevant tests pass
- [ ] `git diff --check` passes
- [ ] Manual verification completed where needed

Commands and scenarios:

```text

```

## Risk

- [ ] Audio capture or conversion
- [ ] STT protocol or reconnection
- [ ] Translation ordering or timeout
- [ ] Permissions or Keychain
- [ ] SwiftData schema or migration
- [ ] Performance or long-running session
- [ ] No material risk in these areas

Mitigation or rollback:

## Security And Privacy

- [ ] No API Key, token, certificate, private Workspace configuration, or raw classroom audio is committed
- [ ] Logs do not expose authorization headers or sensitive request content

## Documentation

- [ ] Development documentation was updated
- [ ] No documentation change is required
