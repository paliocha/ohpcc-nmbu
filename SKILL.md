---
name: ohpcc-nmbu
description: >-
  Submit, monitor, and retrieve SLURM batch jobs on the NMBU Orion HPC cluster
  (or any SLURM cluster reachable over SSH). Use when the user wants to run heavy
  compute on Orion: logging in, syncing inputs up, submitting a batch job,
  checking the queue, or pulling outputs back. Config-driven (hosts, account,
  remote working directory) so it ports across projects unchanged.
---

# ohpcc-nmbu

Offload heavy compute from a laptop to the **Orion HPC cluster** at NMBU. The
laptop stays the source of truth for code; the cluster only runs jobs. Five
small wrappers cover the loop: log in, push inputs, submit, watch the queue,
fetch outputs. Everything project-specific lives in one config file (`hpc.env`).

Ported from [`genomedk-jobs`](https://codeberg.org/cmkobel/genomedk-jobs); it
also works on any SLURM cluster you can reach over SSH.

> **Authoritative reference.** The Orion documentation is at <https://orion.nmbu.no/>
> (behind NMBU login). If anything here is unclear or the cluster has changed
> (partitions, limits, hosts, GPU types), treat that site as the source of truth.

## First read the safety rules

`reference/safety.md` is non-negotiable, especially: **never run compute on the
login node — always `sbatch`** (it kills anything over 5 minutes); all remote
writes confined to `HPC_REMOTE_ROOT`; never `rsync --delete`; no
personal/sensitive/GDPR data; every action audited.

## Enforce the safety rules with a hook (recommended)

`scripts/hpc_guard_hook.py` is a Claude Code **PreToolUse** hook that blocks raw
`ssh <host> 'rm -rf …'` / `rsync --delete` against either configured Orion host.
It only acts in projects that have an `hpc.env` whose host matches, so enabling
it globally is a no-op elsewhere. Add to `settings.json` (`~` is not expanded —
use `$HOME`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 $HOME/.claude/skills/ohpcc-nmbu/scripts/hpc_guard_hook.py" }
        ]
      }
    ]
  }
}
```

## One-time setup per project

1. **SSH aliases with multiplexing.** Add `Host orion` and `Host orion-filemanager`
   blocks to `~/.ssh/config` (see `reference/ssh_setup.md`). Orion uses your NMBU
   username+password; an SSH key makes it prompt-free. Off-campus needs the NMBU
   VPN.
2. **Config.** Run `bash scripts/hpc_init.sh` from your project root — it drops an
   `hpc.env` and gitignores local artifacts. Fill in `HPC_HOST`,
   `HPC_TRANSFER_HOST`, `HPC_ACCOUNT` (`nmbu`), `HPC_REMOTE_ROOT`
   (`/mnt/project/<group>/<you>`), `HPC_PARTITION` (`orion`), `HPC_MAIL_USER`,
   `HPC_PUSH_PATHS`.

## Validate the install

```bash
bash $S/hpc_selftest.sh            # offline: syntax, config, guards, render, audit, wrappers
bash $S/hpc_selftest.sh --online   # also probe Orion read-only (run inside your project)
```

## The workflow

```bash
S=.claude/skills/ohpcc-nmbu/scripts

bash $S/hpc_login.sh                       # warm SSH sockets to both hosts
bash $S/hpc_push.sh                        # rsync HPC_PUSH_PATHS up via the transfer host
python $S/hpc_submit.py --name myjob \
    --command "python work.py" \
    --time 12:00:00 --gpus 1 --partition GPU --cpus 8 --mem 16g
bash $S/hpc_status.sh                       # squeue for you (read-only); pass a jobid for sacct fallback
bash $S/hpc_fetch.sh results/myjob          # rsync a remote subpath back down
```

- **Two hosts.** Submit/status/login use `HPC_HOST` (login node). Push/fetch use
  `HPC_TRANSFER_HOST` (file manager) because the login node kills transfers over
  5 minutes. Leave `HPC_TRANSFER_HOST` unset on a single-host cluster.
- **Probe before authenticating.** `hpc_login.sh` is a no-op when sockets are
  alive. With an SSH key there is no prompt.
- **`hpc_submit.py` is generic.** `--command` is the exact command run on the
  node; `--setup` (or `HPC_JOB_SETUP`) holds env activation; `--dry-run` prints
  the rendered script. `--gpus` defaults to 0 (CPU-only). For a GPU job pass
  `--gpus N --partition GPU`.
- **Long runs: `--chunks N`** emits `#SBATCH --array=1-N%1` (sequential tasks).
  Each task must resume from your checkpoint. Array/chunked jobs are mailed
  `FAIL` only (NMBU's ~200/day email cap); single jobs get `END,FAIL`. To
  checkpoint *before* a walltime kill, add `#SBATCH --signal=B:USR1@120` to your
  `--command`/setup and trap `USR1` — SLURM (24.11 on Orion) delivers it 120 s
  before `--time` expires.
- **Partitions.** `orion` (CPU, default) and `GPU` (uppercase). Never submit to
  the OnDemand partitions. `freecores`/`freenodes` show idle capacity.
- **Status detail.** `hpc_status.sh` runs `squeue`, falling back to `sacct` for
  finished jobs. `ssh $HPC_HOST jobinfo <jobid>` gives a friendly summary
  including CPU/memory/walltime efficiency — use it to right-size your next run.
  (`seff` reports the same, but is currently broken on Orion — a missing perl
  library; prefer `jobinfo`, or `sacct -j <jobid> --format=...,MaxRSS,ReqMem`.)
  For a **still-running** job, `ssh $HPC_HOST sstat -j <jobid>
  --format=JobID,MaxRSS,AveCPU,TRESUsageInMax` gives live memory/CPU (and
  `gres/gpumem`,`gres/gpuutil`) — `sacct` only fills in after it finishes.
  Cancel a job with `ssh $HPC_HOST scancel <jobid>` (or `scancel -n <name>`).
  `ssh $HPC_HOST scontrol show job <jobid>` dumps the full live job record
  (state, reason, node, resources) while it is pending/running. When a job fails
  or won't start, `reference/troubleshooting.md` maps symptoms to fixes.
- **Not wrapped (run directly).** `hpc_submit.py` builds a single-node job
  (`-c` cpus, one task). Multi-node/MPI jobs and "one task per input file" arrays
  aren't covered by the wrapper — write a custom `sbatch` script (see
  `reference/cluster-overview.md`) and submit it with `ssh $HPC_HOST sbatch …`.
  Interactive sessions use `qlogin`/`srun --pty`/Open OnDemand, not these wrappers.

## Dependencies: micromamba (via `module load Miniforge3`)

1. **Commit `environment.yml`** and list it in `HPC_PUSH_PATHS`.
2. **Create the env once on the login/transfer node** (not inside a job):
   ```bash
   ssh $HPC_HOST 'module load Miniforge3 && micromamba create -f <HPC_REMOTE_ROOT>/<HPC_CODE_SUBDIR>/environment.yml -n <env>'
   ```
   Compute nodes do have internet, but creating once is faster and reproducible.
3. **Activate in the job** via `HPC_JOB_SETUP` (the example wires
   `module load Miniforge3; eval "$(micromamba shell hook --shell bash)";
   micromamba activate <env>`), then `--command "python work.py"`. `module` and
   micromamba are available in non-interactive job shells on Orion, so this just
   works. Keep the env's **root prefix consistent**: the create command above and
   the activate here both use micromamba's default root (`~/micromamba`); if you
   set `MAMBA_ROOT_PREFIX`, use the same value in both places or activation fails.

**Using something else?** The skill is manager-agnostic — put `module load …`,
an Apptainer `apptainer exec …`, or a venv activation in `HPC_JOB_SETUP`.

## Worked example: a GPU job on Orion

With `hpc.env` set to `HPC_REMOTE_ROOT=/mnt/project/<group>/you`,
`HPC_CODE_SUBDIR=repo`, and the micromamba `HPC_JOB_SETUP`:

```bash
bash $S/hpc_login.sh
bash $S/hpc_push.sh                                       # src/ scripts/ environment.yml
ssh orion 'module load Miniforge3 && micromamba create -f /mnt/project/<group>/you/repo/environment.yml -n proj'
python $S/hpc_submit.py --name train --gpus 1 --partition GPU --time 12:00:00 \
    --command "python scripts/train.py --device cuda"
# ... SLURM emails END,FAIL ...
bash $S/hpc_fetch.sh results/train
```

For I/O-heavy work, stage inputs to the node-local SSD `$TMPDIR` (up to ~15 TB)
inside `--command` and copy results back to `$PROJECTS` at the end — reading many
small files over NFS is slow and hurts the whole cluster.

The GPU node carries **RTX PRO 6000 Blackwell** cards (compute capability
`sm_120`, ~96 GB VRAM). The Lmod `CUDA` modules cap at 12.1 and `cuDNN` at 8.0.4,
which predate Blackwell — so install deep-learning frameworks via micromamba with
a **CUDA 12.8+ build** (e.g. PyTorch `cu128`) rather than `module load CUDA`. The
driver (590, CUDA 13.1) runs the newer runtime fine. Full details and the live
`nvidia-smi`/`module avail` commands are in `reference/cluster-overview.md`.

## What is in this directory

```
ohpcc-nmbu/
├── SKILL.md                    # this file
├── config/hpc.env.example      # copy to hpc.env at the project root and fill in
├── scripts/
│   ├── _hpc_lib.sh             # config loader + remote-root guard + audit (sourced)
│   ├── _hpc_log.py             # JSONL audit logger
│   ├── hpc_init.sh             # scaffold hpc.env + .gitignore in a new project
│   ├── hpc_login.sh            # warm the SSH sockets (login + transfer)
│   ├── hpc_status.sh           # squeue, with sacct fallback (read-only)
│   ├── hpc_push.sh             # rsync inputs/code up via the transfer host (never --delete)
│   ├── hpc_submit.py           # render template + sbatch + capture jobid
│   ├── hpc_fetch.sh            # rsync outputs down via the transfer host (never --delete)
│   ├── hpc_guard_hook.py       # optional PreToolUse hook: block bypass attempts
│   └── hpc_selftest.sh         # validate the skill (offline; --online probes Orion)
├── templates/job.slurm.tmpl    # generic SBATCH template (@@PLACEHOLDER@@ substitution)
└── reference/
    ├── ssh_setup.md            # the ~/.ssh/config blocks to add
    ├── safety.md               # the hard rules for Orion
    ├── cluster-overview.md     # nodes, GPUs, SLURM config, interactive jobs, snapshots (live-query first)
    └── troubleshooting.md      # diagnose failed / stuck / slow jobs by symptom
```

## Porting and sharing

Self-contained: copy the directory into another project's `.claude/skills/` (or
`~/.claude/skills/`), give it its own `hpc.env`, and it works. For a non-Orion
SLURM cluster, point `hpc.env` at that cluster and leave `HPC_TRANSFER_HOST`
unset to reuse the login host.
