"""ThinkTank CI pipeline — local-first quality gates via Dagger."""

from typing import Annotated

import anyio

import dagger
from dagger import DefaultPath, Doc, Ignore, dag, function, object_type

ELIXIR_IMAGE = "elixir:1.19.0-otp-28"
GITLEAKS_IMAGE = "zricethezav/gitleaks:v8.30.0"
PYTHON_IMAGE = "python:3.13-slim"
SHELLCHECK_IMAGE = "koalaman/shellcheck-alpine:stable"

SOURCE_IGNORE = [
    ".git",
    ".artifacts",
    ".cache",
    ".elixir_ls",
    ".env",
    ".flywheel",
    ".pi/state",
    "_build",
    "ci/.pytest_cache",
    "ci/sdk",
    "ci_logs",
    "cover",
    "deps",
    "erl_crash.dump",
    "thinktank",
    "thinktank.log",
    "tmp",
]


def _elixir_base(source: dagger.Directory) -> dagger.Container:
    return (
        dag.container()
        .from_(ELIXIR_IMAGE)
        .with_exec(
            [
                "sh",
                "-lc",
                "apt-get update -qq"
                " && apt-get install -y -qq --no-install-recommends git build-essential ripgrep"
                " && rm -rf /var/lib/apt/lists/*",
            ]
        )
        .with_env_variable("HEX_HOME", "/root/.hex")
        .with_env_variable("MIX_HOME", "/root/.mix")
        .with_env_variable("LANG", "C.UTF-8")
        .with_env_variable("LC_ALL", "C.UTF-8")
        .with_mounted_cache("/root/.hex", dag.cache_volume("thinktank-ci-hex"))
        .with_mounted_cache("/root/.mix", dag.cache_volume("thinktank-ci-mix"))
        .with_mounted_cache("/root/.cache/rebar3", dag.cache_volume("thinktank-ci-rebar3"))
        .with_directory("/src", source)
        .with_workdir("/src")
        .with_exec(["mix", "local.hex", "--force"])
        .with_exec(["mix", "local.rebar", "--force"])
    )


def _elixir_env(source: dagger.Directory, mix_env: str, cache_key: str) -> dagger.Container:
    return (
        _elixir_base(source)
        .with_env_variable("MIX_ENV", mix_env)
        .with_mounted_cache(
            "/src/deps",
            dag.cache_volume(f"thinktank-ci-deps-{mix_env}-{cache_key}"),
        )
        .with_mounted_cache(
            "/src/_build",
            dag.cache_volume(f"thinktank-ci-build-{mix_env}-{cache_key}"),
        )
        .with_exec(["mix", "deps.get"])
    )


def _python_lint_container(source: dagger.Directory) -> dagger.Container:
    return (
        dag.container()
        .from_(PYTHON_IMAGE)
        .with_exec(["pip", "install", "--quiet", "pyyaml"])
        .with_directory("/src", source)
        .with_workdir("/src")
    )


@object_type
class ThinktankCi:
    """Repo-local CI gates for ThinkTank."""

    @function
    async def elixir_quality(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Run formatting, compile, lint, and dependency audit checks."""
        await (
            _elixir_env(source, "test", "quality")
            .with_exec(["mix", "format", "--check-formatted"])
            .with_exec(["mix", "compile", "--warnings-as-errors"])
            .with_exec(["mix", "credo", "--strict"])
            .with_exec(["mix", "hex.audit"])
            .sync()
        )

    @function
    async def architecture(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Enforce repo-specific architecture boundaries."""
        await _elixir_env(source, "dev", "architecture").with_exec(
            ["scripts/ci/architecture-gate.sh"]
        ).sync()

    @function
    async def backlog(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Enforce backlog file placement and status invariants."""
        await _elixir_base(source).with_exec(["scripts/ci/backlog-state-gate.sh"]).sync()

    @function
    async def harness_agents(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Ensure repo-local harness agent personas do not hardcode models."""
        await _elixir_base(source).with_exec(["scripts/ci/harness-agent-gate.sh"]).sync()

    @function
    async def coveralls(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Run the test suite with the repo's coverage threshold."""
        await _elixir_env(source, "test", "coveralls").with_exec(["mix", "coveralls"]).sync()

    @function
    async def dialyzer(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Run Dialyzer under the development environment."""
        await _elixir_env(source, "dev", "dialyzer").with_exec(["mix", "dialyzer"]).sync()

    @function
    async def escript(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Build the escript and verify the CLI boots."""
        await (
            _elixir_env(source, "test", "escript")
            .with_exec(["mix", "escript.build"])
            .with_exec(["./thinktank", "--help"])
            .sync()
        )

    @function
    async def e2e_smoke(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Build the escript and run the CLI e2e smoke suite."""
        await (
            _elixir_env(source, "test", "escript")
            .with_exec(["mix", "escript.build"])
            .with_exec(
                [
                    "mix",
                    "test",
                    "--include",
                    "e2e",
                    "test/thinktank/e2e/smoke_test.exs",
                ]
            )
            .sync()
        )

    @function
    async def shell(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Run shellcheck on repo scripts and native git hooks."""
        await (
            dag.container()
            .from_(SHELLCHECK_IMAGE)
            .with_directory("/src", source)
            .with_workdir("/src")
            .with_exec(
                [
                    "sh",
                    "-lc",
                    "find . -type f \\( -name '*.sh' -o -path './.githooks/*' \\)"
                    " -exec shellcheck --severity=error {} +",
                ]
            )
            .sync()
        )

    @function
    async def yaml(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Validate repository YAML files parse correctly."""
        script = r"""
from pathlib import Path
import yaml

paths = sorted(Path(".").rglob("*.yml")) + sorted(Path(".").rglob("*.yaml"))
for path in paths:
    yaml.safe_load(path.read_text())
"""
        await _python_lint_container(source).with_exec(["python", "-c", script]).sync()

    @function
    async def models(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Validate hardcoded model IDs against the live OpenRouter catalog."""
        await _python_lint_container(source).with_exec(
            [
                "python",
                "scripts/validate_elixir_models.py",
                "--repo-root",
                "/src",
                "--fail-on-unreachable",
            ]
        ).sync()

    @function
    async def security(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Run repo-owned static security checks."""
        await _elixir_base(source).with_exec(["scripts/ci/security-gate.sh"]).sync()

    @function
    async def gitleaks(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> None:
        """Scan the repository for hardcoded secrets."""
        await (
            dag.container()
            .from_(GITLEAKS_IMAGE)
            .with_directory("/src", source)
            .with_workdir("/src")
            .with_exec(
                [
                    "gitleaks",
                    "dir",
                    "/src",
                    "--no-banner",
                    "--redact",
                    "--exit-code",
                    "1",
                ]
            )
            .sync()
        )

    @function
    async def check(
        self,
        source: Annotated[
            dagger.Directory,
            DefaultPath("/"),
            Ignore(SOURCE_IGNORE),
            Doc("Repo source directory"),
        ],
    ) -> str:
        """Run all repo-local CI gates and return a compact summary."""
        results: list[tuple[str, bool, str]] = []

        async def run_gate(name: str, gate) -> None:
            try:
                await gate
                results.append((name, True, "OK"))
            except dagger.ExecError as error:
                detail = (error.stdout or error.stderr or str(error)).strip()
                results.append((name, False, detail or str(error)))
            except Exception as error:
                results.append((name, False, str(error)))

        async with anyio.create_task_group() as tg:
            tg.start_soon(run_gate, "backlog", self.backlog(source))
            tg.start_soon(run_gate, "gitleaks", self.gitleaks(source))
            tg.start_soon(run_gate, "harness-agents", self.harness_agents(source))
            tg.start_soon(run_gate, "models", self.models(source))
            tg.start_soon(run_gate, "security", self.security(source))
            tg.start_soon(run_gate, "shell", self.shell(source))
            tg.start_soon(run_gate, "yaml", self.yaml(source))
            await run_gate("elixir-quality", self.elixir_quality(source))
            await run_gate("architecture", self.architecture(source))
            await run_gate("coveralls", self.coveralls(source))
            await run_gate("dialyzer", self.dialyzer(source))
            await run_gate("escript", self.escript(source))
            await run_gate("e2e-smoke", self.e2e_smoke(source))

        lines = ["ThinkTank CI Results", "=" * 40]
        passed = 0
        failed = 0

        for name, ok, message in sorted(results):
            lines.append(f"  {'PASS' if ok else 'FAIL'}  {name}")
            if ok:
                passed += 1
                continue

            failed += 1
            for line in message.splitlines()[:8]:
                lines.append(f"         {line}")

        lines.append("=" * 40)
        lines.append(f"{passed} passed, {failed} failed")

        summary = "\n".join(lines)
        if failed > 0:
            raise Exception(summary)

        return summary
