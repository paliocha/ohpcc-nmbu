# ohpcc-nmbu

A [Claude Code](https://docs.claude.com/en/docs/claude-code) Agent Skill for running SLURM batch jobs on the **NMBU Orion HPC cluster** without leaving your laptop. Your laptop stays the source of truth for code; the cluster only runs jobs. The assistant drives a small, auditable set of wrappers to log in, push inputs, submit, watch the queue, and fetch results back.

Config-driven through a single `hpc.env` file, so the same skill works across all your projects unchanged — and ports to any SSH-reachable SLURM cluster.

Ported from [`genomedk-jobs`](https://codeberg.org/cmkobel/genomedk-jobs) (Carl M. Kobel, Aarhus GenomeDK), adapted for Orion at NMBU.

---

## Why

Running heavy compute on a shared cluster from an AI assistant is useful but risky: a stray `rm -rf`, a runaway login-node process, a transfer that wipes a colleague's results. The skill is built to prevent that:

- One config per project. Everything cluster- and project-specific lives in `hpc.env`; the scripts stay generic.
- Writes are confined to a single `HPC_REMOTE_ROOT` you own. Paths are checked against shell injection and `..` traversal, and `rsync` never uses `--delete`.
- Transfers go through Orion's file-transfer host, because the login node kills anything over 5 minutes.
- Every action appends one JSON line to a local audit log (intent and outcome only, never data).
- An optional PreToolUse hook blocks destructive bypass commands (`rm -rf`, `rsync --delete`) at the harness level.

---

## What's in the box

```
ohpcc-nmbu/
├── SKILL.md                    # full operating manual (the assistant reads this)
├── config/hpc.env.example      # copy to hpc.env at your project root and fill in
├── scripts/
│   ├── _hpc_lib.sh             # config loader + safety guards + audit (sourced)
│   ├── _hpc_log.py             # JSONL audit logger
│   ├── hpc_init.sh             # scaffold hpc.env + .gitignore in a new project
│   ├── hpc_login.sh            # warm the SSH sockets (login + transfer)
│   ├── hpc_push.sh             # rsync inputs/code up (never --delete)
│   ├── hpc_submit.py           # render template + sbatch + capture jobid
│   ├── hpc_status.sh           # squeue, with sacct fallback for finished jobs
│   ├── hpc_fetch.sh            # rsync outputs down (never --delete)
│   ├── hpc_guard_hook.py       # optional PreToolUse hook: block bypass attempts
│   └── hpc_selftest.sh         # validate the skill (offline; --online probes Orion)
├── templates/job.slurm.tmpl    # generic SBATCH template (@@PLACEHOLDER@@ substitution)
└── reference/
    ├── ssh_setup.md            # the ~/.ssh/config blocks to add
    ├── safety.md               # the hard rules for a shared cluster
    └── cluster-overview.md     # nodes, partitions, modules, snapshot recovery
```

---

## Requirements

- An Orion account (`https://orion.nmbu.no/` → *Getting Started*). Off-campus needs the NMBU VPN.
- Local `bash`, `python3` (stdlib only), `rsync`, and OpenSSH. No other dependencies.
- Claude Code (or any agent that loads Agent Skills). The wrappers are plain scripts and also work by hand.

---

## Install

```bash
# Global (available in every project):
cp -r ohpcc-nmbu ~/.claude/skills/ohpcc-nmbu

# …or per-project:
cp -r ohpcc-nmbu <your-project>/.claude/skills/ohpcc-nmbu
```

### 1. SSH config (one-time per machine)

Add aliases for both Orion hosts to `~/.ssh/config` (full block in `reference/ssh_setup.md`):

```sshconfig
Host orion
    HostName login.orion.nmbu.no
    User <your-nmbu-username>
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 12h

Host orion-filemanager
    HostName filemanager.orion.nmbu.no
    User <your-nmbu-username>
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 12h
```

With an SSH key set up on Orion this is prompt-free. If `orion-filemanager` ever fails host-key verification, run `ssh-keygen -R filemanager.orion.nmbu.no` and reconnect to accept the new key.

### 2. Scaffold a project

```bash
cd <your-project>
bash ~/.claude/skills/ohpcc-nmbu/scripts/hpc_init.sh   # drops hpc.env + gitignores artifacts
$EDITOR hpc.env                                        # fill in the values below
```

### 3. Validate

```bash
bash ~/.claude/skills/ohpcc-nmbu/scripts/hpc_selftest.sh            # offline machinery checks
bash ~/.claude/skills/ohpcc-nmbu/scripts/hpc_selftest.sh --online   # read-only probe of real Orion
```

---

## Configuration (`hpc.env`)

| Key | What it is | Orion value / example |
|-----|------------|-----------------------|
| `HPC_HOST` | SSH alias for the **login** node (shell + sbatch) | `orion` |
| `HPC_TRANSFER_HOST` | SSH alias for the **transfer** node (rsync/scp). Omit to reuse `HPC_HOST` | `orion-filemanager` |
| `HPC_USER` | Your NMBU/Orion username | `abcd` |
| `HPC_ACCOUNT` | SLURM account to charge | `nmbu` |
| `HPC_REMOTE_ROOT` | **The write boundary.** Absolute path you own; all writes are confined here | `/mnt/project/<group>/<you>` |
| `HPC_PARTITION` | Default partition | `orion` (CPU) or `GPU` |
| `HPC_MAIL_USER` | Email for SLURM notifications (blank = off) | `you@nmbu.no` |
| `HPC_CODE_SUBDIR` | Subdir under the root for pushed code / job CWD | `repo` |
| `HPC_PUSH_PATHS` | What `hpc_push.sh` (no args) syncs up | `"src scripts environment.yml"` |
| `HPC_JOB_SETUP` | Shell lines run in every job before your command (env activation) | micromamba block, below |

`hpc.env` holds no secrets and is safe to commit and share with collaborators on the same project.

---

## Quickstart

```bash
S=~/.claude/skills/ohpcc-nmbu/scripts

bash $S/hpc_login.sh                       # warm SSH sockets to both hosts
bash $S/hpc_push.sh                         # rsync HPC_PUSH_PATHS up (via the transfer host)
python3 $S/hpc_submit.py --name train \
    --command "python train.py --device cuda" \
    --gpus 1 --partition GPU --cpus 8 --mem 32g --time 12:00:00
bash $S/hpc_status.sh                        # your queue; pass a jobid for sacct detail
bash $S/hpc_fetch.sh results/train           # rsync a remote subpath back down
```

`hpc_submit.py --dry-run` prints the rendered SLURM script without submitting. `hpc_push.sh --dry-run` / `hpc_fetch.sh --dry-run` preview transfers.

---

## The two-host model

Orion separates **control** from **data movement**, and so does this skill:

| Operation | Host used | Why |
|-----------|-----------|-----|
| `hpc_login.sh`, `hpc_submit.py`, `hpc_status.sh` | `HPC_HOST` (`login.orion.nmbu.no`) | submitting and querying SLURM is lightweight |
| `hpc_push.sh`, `hpc_fetch.sh`, root-ownership check, audit merge | `HPC_TRANSFER_HOST` (`filemanager.orion.nmbu.no`) | the login node kills any command over 5 minutes, so real transfers use the data host |

Both hosts share the same filesystems. On a single-host cluster, leave `HPC_TRANSFER_HOST` unset and everything routes through `HPC_HOST`.

---

## Environments (micromamba)

The recommended Orion pattern. Commit an `environment.yml`, push it with your code, create the env **once** on the cluster, then activate it inside each job:

```bash
# one-time, on the login or transfer node:
ssh orion 'module load Miniforge3 && micromamba create -f /mnt/project/<group>/<you>/repo/environment.yml -n proj'
```

```sh
# in hpc.env — runs at the top of every job:
HPC_JOB_SETUP='module load Miniforge3; export MAMBA_ROOT_PREFIX=$HOME/.micromamba_root; eval "$(micromamba shell hook --shell bash)"; micromamba activate proj'
```

The skill is manager-agnostic: put `module load …`, an Apptainer `apptainer exec …`, or a venv activation in `HPC_JOB_SETUP` instead.

For I/O-heavy work, stage inputs to the node-local SSD `$TMPDIR` (up to ~15 TB) and copy results back to `$PROJECTS` at the end; reading many small files over NFS is slow and hurts the whole cluster.

---

## Orion facts baked in

- **Partitions:** `orion` (CPU, default) and `GPU` (uppercase — lowercase `gpu` is rejected by sbatch). The OnDemand partitions (`RStudio`/`JupyterLab`/`OOD`/`TestLab`) are interactive-only; never `sbatch` to them.
- **Storage:** `$HOME` `/mnt/users/<u>` (200–300 GB) · `$SCRATCH` `/mnt/SCRATCH/<u>` (500 GB–1 TB, **purged after 180 days**) · `$PROJECTS` `/mnt/project/<group>` (persistent) · `$TMPDIR` per-node SSD.
- **Walltime:** no default; always set `--time`.
- **Email:** NMBU caps outbound mail at ~200/day, so array/chunked jobs are automatically clamped to `--mail-type FAIL`; single jobs get `END,FAIL`.
- **Monitoring:** `jobinfo <jobid>` for a friendly efficiency summary (`seff` reports the same but is currently broken on Orion); `freecores` / `freenodes` for idle capacity.

---

## Long runs: `--chunks`

`--chunks N` emits `#SBATCH --array=1-N%1` — N tasks that queue but run one at a time, each resuming from your checkpoint. This chains a multi-day run as a sequence of shorter tasks (only useful if your command resumes from a checkpoint on restart).

---

## Safety

`reference/safety.md` is the contract. In short: never run compute on the login node (always `sbatch`); writes confined to `HPC_REMOTE_ROOT`; `rsync` never deletes; **no personal/sensitive/GDPR data on Orion**; right-size resources and check `jobinfo`; every action audited.

Optional hard enforcement — add a PreToolUse hook so the agent harness blocks raw destructive commands (`ssh host 'rm -rf …'`, `rsync --delete`) against your cluster. It only acts in projects with a matching `hpc.env`, so it's safe to enable globally:

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

---

## Porting to another SLURM cluster

The scripts are generic. Point `hpc.env` at another cluster's host / account / partition / root, leave `HPC_TRANSFER_HOST` unset (or set it if that cluster also splits transfer from login), and adjust `HPC_JOB_SETUP`. Trim any Orion-specific notes you don't need.

---

## License

MIT. See [LICENSE](LICENSE).
