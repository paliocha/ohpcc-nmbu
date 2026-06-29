# ohpcc-nmbu

A Claude Code Agent Skill for running SLURM batch jobs on the **NMBU Orion HPC
cluster** from a laptop: log in, push inputs, submit, watch the queue, fetch
results. Config-driven via a single `hpc.env`; portable to any SSH-reachable
SLURM cluster.

Ported from [`genomedk-jobs`](https://codeberg.org/cmkobel/genomedk-jobs).

## Install

```bash
cp -r ohpcc-nmbu ~/.claude/skills/ohpcc-nmbu      # or into a project's .claude/skills/
```

Then, in a project: add the SSH blocks from `reference/ssh_setup.md`, run
`bash ~/.claude/skills/ohpcc-nmbu/scripts/hpc_init.sh`, fill in `hpc.env`, and
validate with `bash scripts/hpc_selftest.sh`.

## Orion specifics

- Two hosts: `login.orion.nmbu.no` (shell + sbatch) and
  `filemanager.orion.nmbu.no` (data transfer — the login node kills commands
  over 5 minutes).
- Partitions `orion` (CPU) and `GPU`. Account `nmbu`. Storage under
  `/mnt/project/<group>`. Environments via `module load Miniforge3` (micromamba).
- No personal/sensitive/GDPR data. See `reference/safety.md`.

See `SKILL.md` for the full operating manual.
