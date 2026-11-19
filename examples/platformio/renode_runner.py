"""Run the selected PlatformIO firmware in the workspace Renode model."""

import os
from pathlib import Path
import subprocess

Import("env")


def simulate(target, source, env):
    project = Path(env.subst("$PROJECT_DIR"))
    lab = project.parent.parent
    settings = dict(os.environ, UNI_SIM_ELF=source[0].get_abspath())
    return subprocess.run(
        ["bash", str(lab / "tools/simulate.sh"), env.subst("$PIOENV")],
        cwd=lab,
        env=settings,
    ).returncode


env.AddCustomTarget(
    name="renode",
    dependencies=["$BUILD_DIR/${PROGNAME}.elf"],
    actions=[simulate],
    title="Renode UART smoke test",
)
