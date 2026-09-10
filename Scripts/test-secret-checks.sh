#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
scanner="$(command -v "${GITLEAKS_BIN:-gitleaks}")"
[[ "$scanner" = /* ]] || scanner="$PWD/$scanner"
export GITLEAKS_BIN="$scanner"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/lecturecaption-scan-tests.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
cp "$root/.gitleaks.toml" "$root/.gitignore" "$fixture/"
mkdir "$fixture/Scripts"
cp "$root/Scripts/check-secrets.sh" "$fixture/Scripts/"
cd "$fixture"
git init -q
git config user.name 'Security Fixture'
git config user.email 'fixture@example.invalid'
git config commit.gpgsign false
git add .
git -c core.hooksPath=/dev/null commit -qm 'clean fixture'
expect_status() {
    expected="$1"
    shift
    status=0
    "$@" > "$fixture/result.log" 2>&1 || status=$?
    if [[ "$status" != "$expected" ]]; then
        echo "FAIL: expected $expected, got $status: $*" >&2
        cat "$fixture/result.log" >&2
        exit 1
    fi
}
expect_redacted() {
    if rg -F "$secret" "$fixture/result.log" >/dev/null; then
        echo 'FAIL: scanner leaked synthetic secret' >&2
        exit 1
    fi
}
for mode in staged worktree history; do
    expect_status 0 bash Scripts/check-secrets.sh "$mode"
done
for path in Release/test.app Sessions.json nested/Sessions.json APIUsage.json LocalCredentials.json test.pem test.key test.pfx; do
    git check-ignore -q "$path"
done
if git check-ignore -q Sources/Example.swift; then exit 1; fi
expect_status 64 bash Scripts/check-secrets.sh unknown
expect_status 69 env GITLEAKS_BIN=/nonexistent/gitleaks bash Scripts/check-secrets.sh staged
printf '#!/bin/sh\nprintf "0.0.0\\n"\n' > wrong-version
chmod +x wrong-version
expect_status 69 env GITLEAKS_BIN="$fixture/wrong-version" bash Scripts/check-secrets.sh staged
rm wrong-version
# Construct a synthetic provider-shaped key without storing a key in the source.
secret="sk-$(printf 'a%.0s' {1..32})"
printf '%s\n' "$secret" > sample.txt
expect_status 1 bash Scripts/check-secrets.sh worktree
expect_redacted
# Neither inline allow comments nor fingerprint ignores may bypass the gate.
printf '%s # gitleaks:allow\n' "$secret" > sample.txt
printf 'sample.txt:lecturecaption-provider-key:1\n' > .gitleaksignore
expect_status 1 bash Scripts/check-secrets.sh worktree
expect_redacted
rm .gitleaksignore
git add sample.txt
expect_status 1 bash Scripts/check-secrets.sh staged
expect_redacted
git -c core.hooksPath=/dev/null commit -qm 'synthetic secret'
git rm -q sample.txt
git -c core.hooksPath=/dev/null commit -qm 'remove synthetic secret'
expect_status 0 bash Scripts/check-secrets.sh worktree
expect_status 1 bash Scripts/check-secrets.sh history
expect_redacted
# Synthetic PEM marker; not a usable private key.
printf '%s\n' '-----BEGIN PRIVATE KEY-----' "$(printf 'c3ludGhldGlj%.0s' {1..8})" '-----END PRIVATE KEY-----' > private-fixture.txt
expect_status 1 bash Scripts/check-secrets.sh worktree
rm private-fixture.txt
# Ignoring an already tracked file cannot hide it from worktree scanning.
printf '%s\n' "$secret" > sample.key
git add -f sample.key
expect_status 1 bash Scripts/check-secrets.sh worktree
expect_status 1 bash Scripts/check-secrets.sh staged
git rm -q --cached sample.key
rm sample.key
ln -s /etc/hosts linked-file
expect_status 65 bash Scripts/check-secrets.sh worktree
echo 'Local security integration tests passed.'
