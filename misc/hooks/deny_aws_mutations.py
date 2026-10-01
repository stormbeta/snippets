#!/usr/bin/env python3
"""PreToolUse(Bash) guard that denies AWS CLI operations which mutate AWS state.

Companion to deny_git_mutations.py, sharing its shell-scanning machinery
(shell_scan): command chaining, subshells, nested shells, and wrappers
(AWS_PROFILE=x aws ..., env, sudo, xargs, bash -c '...') cannot hide the
service/operation. Deny-by-default: an operation is allowed only when it is
provably read-only — a read prefix (get-, list-, describe-, head-, batch-get-,
simulate-) or an explicit exception. Unknown operations fail closed.

Read-only transfers out of S3 are allowed (the s3:// URI in source position);
uploads and server-side copies are denied.

Stdlib only and no subprocesses: this runs on every Bash tool call, and each
added dependency is another way for the guard to stop working.

Self-test: python3 test_deny_aws_mutations.py
"""

from __future__ import annotations

import json
import sys
from collections.abc import Sequence
from dataclasses import dataclass

import shell_scan

__all__ = ["DEFAULT_POLICY", "AwsCommandGuard", "LexError"]

# re-exported so consumers of this module see the same failure type the guard raises
from shell_scan import LexError


@dataclass(frozen=True)
class AwsGuardPolicy:
    """What counts as a mutation. Frozen so a lexing pass cannot alter policy."""

    # Operation prefixes that are reads in every AWS service.
    read_only_prefixes: frozenset[str] = frozenset(
        {"get-", "list-", "describe-", "head-", "batch-get-", "simulate-"}
    )

    # (service, operation) reads that do not fit the prefixes:
    # s3 ls/presign do no mutation; logs tail reads logs; dynamodb query/scan
    # read tables; configure get/list read local CLI config.
    read_only_exact: frozenset[tuple[str, str]] = frozenset(
        {
            ("s3", "ls"),
            ("s3", "presign"),  # computes a URL locally, no API call
            ("logs", "tail"),
            ("dynamodb", "query"),
            ("dynamodb", "scan"),
            ("configure", "get"),
            ("configure", "list"),
        }
    )

    # s3 high-level subcommands that transfer data; classified by direction
    # (see _classify_s3_transfer).
    s3_transfer: frozenset[str] = frozenset({"cp", "mv", "sync"})

    # aws global options that consume the following token. Superset across
    # awscli v1 and v2; a missing entry mis-shifts parsing, which defaults to
    # a denial — the safe direction.
    arg_taking_globals: frozenset[str] = frozenset(
        {
            "--profile", "--region", "--output", "--endpoint-url",
            "--endpoint-urls", "--ca-bundle", "--cli-connect-timeout",
            "--cli-read-timeout", "--color", "--query", "--cli-input-json",
            "--cli-input-yaml", "--pager", "--cli-auto-prompt",
        }
    )

    # Bare aws invocations that carry no service and are harmless.
    no_service_allowed: frozenset[str] = frozenset({"--version", "--help", "-h"})


DEFAULT_POLICY = AwsGuardPolicy()


class AwsCommandGuard:
    """Finds mutating aws operations anywhere in a shell command string."""

    def __init__(self, policy: AwsGuardPolicy = DEFAULT_POLICY) -> None:
        self._policy = policy

    def find_denied_operation(self, command: str) -> str | None:
        """Return the offending 'aws service op', or None if the command may proceed.

        Raises LexError when the command cannot be lexed; callers must treat
        that as a denial rather than an allow.
        """
        return shell_scan.scan_segments(command, self._inspect_segment)

    def _inspect_segment(self, head_name: str, rest: Sequence[str]) -> str | None:
        if head_name != "aws":
            return None
        return self._classify(rest)

    def _classify(self, rest: Sequence[str]) -> str | None:
        if not rest:
            return "aws (no operation)"
        index = 0
        while index < len(rest):
            token = rest[index]
            if not token.startswith("-"):
                break
            if "=" in token:
                index += 1  # --flag=value
            elif token in self._policy.arg_taking_globals:
                index += 2  # --flag value
            else:
                index += 1  # bare flag, e.g. --no-cli-pager
        else:
            # only flags, no service: harmless only for --version/--help
            if all(arg in self._policy.no_service_allowed for arg in rest):
                return None
            return "aws (no operation)"

        service = rest[index]
        if index + 1 >= len(rest):
            return f"aws {service} (no operation)"

        operation = rest[index + 1]
        label = f"aws {service} {operation}"

        if (service, operation) in self._policy.read_only_exact:
            return None
        if service == "s3":
            return self._classify_s3(operation, rest[index + 2 :], label)
        if operation.startswith(tuple(self._policy.read_only_prefixes)):
            return None
        return label

    def _classify_s3(
        self, operation: str, trailing: Sequence[str], label: str
    ) -> str | None:
        if operation == "ls":
            return None
        if operation not in self._policy.s3_transfer:
            return label  # rm, rb, mb, website, ... all mutate

        # A transfer mutates state unless every s3:// URI is the source and a
        # local path is the destination: downloads write only to local disk.
        # "-" is a path (stdin/stdout), not a flag, so it is positional.
        positionals = [t for t in trailing if not (t.startswith("-") and t != "-")]
        is_download = (
            len(positionals) == 2
            and positionals[0].startswith("s3://")
            and not positionals[1].startswith("s3://")
        )
        return None if is_download else label


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
    guard = AwsCommandGuard()
    hook = __file__.rsplit("/", 1)[-1]

    # Deliberately broad: this is a guard, so any failure to understand the
    # command must block, never wave it through.
    try:
        command = extract_command(raw)
        found = guard.find_denied_operation(command)
    except Exception as exc:
        deny(
            f"Blocked: the AWS-mutation guard ({hook}) could not inspect this command "
            f"and is failing closed: {type(exc).__name__}: {exc}. "
            "Report this to the user rather than retrying."
        )
        return 0

    if found is not None:
        deny(
            f"Blocked: '{found}' can mutate AWS state and is denied by the user's "
            f"global hook ({hook}): only provably read-only operations "
            "(get-, list-, describe-, head-, batch-get-, simulate- prefixes, plus "
            "explicit exceptions like 'aws s3 ls') are allowed, and s3 cp/mv/sync "
            "only when downloading. This applies regardless of '--profile', "
            "'--region', '--endpoint-url', chaining, or nested shells. Do not look "
            "for a workaround: tell the user the exact command you need and let "
            "them run it."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
