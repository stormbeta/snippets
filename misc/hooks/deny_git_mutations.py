#!/usr/bin/env python3
"""PreToolUse(Bash) guard that denies git subcommands which mutate local state.

Exists because settings.json permission patterns are literal prefix matches, so
"Bash(git restore*)" does not match "git -C /repo restore ...", and no deny
pattern matches the right-hand side of "cd /repo && git restore ...". This hook
lexes the command instead (via shell_scan), so global options, command
chaining, nested shells, and quoting cannot hide the subcommand.

Read-only operations stay allowed, including read-only forms of dual-purpose
subcommands (`git stash list`, `git config --get`, `git branch --list`, ...).

Stdlib only and no subprocesses: this runs on every Bash tool call, and each
added dependency is another way for the guard to stop working.

Self-test: python3 test_deny_git_mutations.py
"""

from __future__ import annotations

import json
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field

import shell_scan
from shell_scan import LexError  # re-exported for the test suite

# re-exported for consumers that scanned the module's surface
__all__ = ["DEFAULT_POLICY", "GitCommandGuard", "LexError"]


@dataclass(frozen=True)
class GitGuardPolicy:
    """What counts as a mutation. Frozen so a lexing pass cannot alter policy."""

    # Subcommands that always change the index, working tree, refs, object
    # store, or stash.
    denied: frozenset[str] = frozenset(
        {
            "add", "am", "apply", "bisect", "checkout", "cherry-pick", "clean",
            "commit", "fast-import", "filter-branch", "gc", "merge", "mv",
            "prune", "push", "rebase", "repack", "replace", "reset", "restore",
            "rm", "revert", "switch", "symbolic-ref", "update-index",
            "update-ref", "write-tree",
        }
    )

    # Subcommands that both read and write: denied unless an explicitly
    # read-only flag or verb appears in their arguments.
    readonly_forms: Mapping[str, frozenset[str]] = field(
        default_factory=lambda: {
            "branch": frozenset(
                {"--list", "-l", "--show-current", "--contains", "--merged",
                 "--no-merged", "-a", "--all", "-r", "--remotes"}
            ),
            "config": frozenset(
                {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"}
            ),
            "notes": frozenset({"list", "show"}),
            "reflog": frozenset({"show"}),
            "remote": frozenset({"-v", "--verbose", "show", "get-url"}),
            "stash": frozenset({"list", "show"}),
            "submodule": frozenset({"status", "summary", "foreach"}),
            "tag": frozenset({"-l", "--list", "--contains", "--points-at"}),
            "worktree": frozenset({"list"}),
        }
    )

    # git global options that consume the following token.
    arg_taking_globals: frozenset[str] = frozenset(
        {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
    )

    @property
    def all_gated(self) -> frozenset[str]:
        return self.denied | frozenset(self.readonly_forms)


DEFAULT_POLICY = GitGuardPolicy()


class GitCommandGuard:
    """Finds mutating git subcommands anywhere in a shell command string."""

    def __init__(self, policy: GitGuardPolicy = DEFAULT_POLICY) -> None:
        self._policy = policy

    def find_denied_subcommand(self, command: str) -> str | None:
        """Return the offending subcommand, or None if the command may proceed.

        Raises LexError when the command cannot be lexed; callers must treat
        that as a denial rather than an allow.
        """
        return shell_scan.scan_segments(command, self._inspect_segment)

    def _inspect_segment(self, head_name: str, rest: Sequence[str]) -> str | None:
        if head_name != "git":
            return None
        return self._subcommand_of(rest)

    def _subcommand_of(self, rest: Sequence[str]) -> str | None:
        index = 0
        while index < len(rest):
            token = rest[index]
            if not token.startswith("-"):
                break
            index += 2 if token in self._policy.arg_taking_globals else 1
        else:
            return None

        subcommand = rest[index]
        if subcommand not in self._policy.all_gated:
            return None

        allowed_forms = self._policy.readonly_forms.get(subcommand)
        if allowed_forms is not None:
            arguments = rest[index + 1 :]
            if any(arg.split("=", 1)[0] in allowed_forms for arg in arguments):
                return None
        return subcommand


def deny(reason: str) -> None:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.stdout.write("\n")


def extract_command(raw: str) -> str:
    """Pull the Bash command out of a PreToolUse payload, or raise."""
    payload = json.loads(raw)
    command = payload["tool_input"]["command"]
    if not isinstance(command, str):
        raise TypeError(f"tool_input.command is {type(command).__name__}, expected str")
    return command


def main() -> int:
    raw = sys.stdin.read()
    guard = GitCommandGuard()
    hook = __file__.rsplit("/", 1)[-1]

    # Deliberately broad: this is a guard, so any failure to understand the
    # command must block. The bug this file replaces was a silent allow-all.
    try:
        command = extract_command(raw)
        found = guard.find_denied_subcommand(command)
    except Exception as exc:
        deny(
            f"Blocked: the git-mutation guard ({hook}) could not inspect this command "
            f"and is failing closed: {type(exc).__name__}: {exc}. "
            "Report this to the user rather than retrying."
        )
        return 0

    if found is not None:
        deny(
            f"Blocked: 'git {found}' mutates local repository state and is denied by the "
            f"user's global hook ({hook}). This applies regardless of 'git -C', "
            "'--git-dir', chaining, or nested shells. Do not look for a workaround: "
            "tell the user the exact command you need and let them run it."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
