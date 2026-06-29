# Cluster overview (Orion, NMBU)

Hardware and software change as nodes are added or modules are rebuilt, so
**always confirm live** rather than trusting a static list. The snapshot below
was current on 2026-06-29; the commands are the source of truth.

## Query it live

```bash
sinfo -N -o "%N %c %m %G %P"     # per node: name, CPUs, memory(MB), GRES(GPUs), partition
sinfo -o "%P %a %l %D"           # per partition: name, avail, timelimit, node count
gnodes                            # Orion helper: per-node load + free cores, visual
freecores | sort -V               # Orion helper: free cores per node
freenodes                         # Orion helper: which nodes are fully idle
scontrol show node <name>         # everything about one node
nvidia-smi                        # on a GPU node (via a job): live GPU model/VRAM/util
module avail                      # all software modules
module spider <name>              # every version of one tool + how to load it
```

## Partitions (batch)

| Partition | Use | Nodes |
|-----------|-----|-------|
| `orion` (default) | CPU work, any memory | `cn-31`–`cn-35`, `cn-37` |
| `GPU` | anything that uses a GPU | `gn-41` |

`RStudio`, `JupyterLab`, `OOD`, `TestLab` exist but are for Open OnDemand
interactive apps — do not `sbatch` to them. Note `GPU` is uppercase; lowercase
`gpu` is rejected by sbatch. No partition enforces a default walltime, so always
set `--time`.

## Nodes (snapshot 2026-06-29)

| Node(s) | Partition | Logical CPUs | Memory | GPUs |
|---------|-----------|--------------|--------|------|
| `cn-31`–`cn-35`, `cn-37` | `orion` | 384 (192 physical cores, SMT2) | ~1.5 TB (1547036 MB) | — |
| `gn-41` | `GPU` | 384 | ~1.5 TB (1546510 MB) | 7× `rtxpro6000` (RTX PRO 6000 Blackwell) |
| `cn-36` | OOD/RStudio/JupyterLab | 384 | ~1.5 TB | — |
| `cn-25` | TestLab | 56 | ~371 GB (380000 MB) | — |

Slurm default memory is 3 GB per CPU if you don't set `--mem`. Request GPUs with
`--gpus N` (it avoids hardcoding the GRES name, which can change as cards are
added); confirm the live GRES with `sinfo -o "%n %G"`.

The table above lists the **batch-schedulable** nodes you can `sbatch` to. The
full cluster is larger and heterogeneous — per the wiki *Cluster overview*: **25
compute nodes, 4,736 CPU cores, 23.5 TB RAM, 11 GPUs (8× Blackwell + 3× Quadro
RTX 8000), 3.2 PB parallel storage (IBM ESS / GPFS, exported over NFS)**, mixing
AMD EPYC and Intel Xeon generations, RHEL 9 (most) or 10 (newest). Node-local
`$TMPDIR` ranges ~3–15 TB NVMe depending on node; the newest nodes have 100 Gbit
to storage. Older CPU nodes and the RTX 8000 GPUs are not currently exposed as
partitions you can submit to — `sinfo` shows what you can actually use.

## GPUs (`GPU` partition, node `gn-41`)

Snapshot 2026-06-29 (confirm with `nvidia-smi` inside a GPU job):

- **7× NVIDIA RTX PRO 6000 Blackwell Server Edition** per node, **~96 GB VRAM**
  each (97887 MiB), compute capability **12.0** (`sm_120`), 600 W, MIG disabled.
- Driver **590.48.01**, which supports CUDA runtimes up to **13.1** (only a
  toolkit *newer* than that would fail to run).
- The node is built with 8 Blackwell cards; `sinfo` currently exposes **7** as
  schedulable (`gpu:rtxpro6000:7`) — trust `sinfo -o "%n %G"` for the live count.
  The cluster also has **3× Quadro RTX 8000** (Turing, 48 GB) on older AMD nodes,
  but those are not currently in a partition you can `sbatch` to.
- Request with `--partition GPU --gpus N` (1–7 per node). Verify in the job:
  ```bash
  #SBATCH --partition=GPU
  #SBATCH --gpus=1
  nvidia-smi
  ```
- `nvidia-smi` is installed and configured on the GPU node (driver 590.48.01);
  it is **not** present on the login node (no GPU there). SLURM sets
  `CUDA_VISIBLE_DEVICES` to your allocation — trust that and your framework's
  device count; `nvidia-smi` may list more of the node's GPUs than you were
  granted.

**Toolkit caveat — important for Blackwell.** The Lmod CUDA modules top out at
**CUDA 12.1** (`module load CUDA/12.1.1`, `nvcc` 12.1.105) and the only `cuDNN`
module is **8.0.4**; both predate Blackwell `sm_120`, so code built against them
will not produce Blackwell-native kernels (and old framework binaries may fail
or fall back to slow paths). For deep-learning frameworks, install via micromamba
with a **CUDA 12.8+ build** — e.g. a recent PyTorch `cu128`/`cu129` wheel or
conda `pytorch` with a matching `pytorch-cuda` — the driver (CUDA 13.1) runs
those newer runtimes fine. `module load CUDA` is OK only for plain CUDA ≤12.1
work that does not need `sm_120`.

GPU-relevant modules available: `CUDA` 10.1 / 11.1 / 11.7 / 12.1, `cuDNN` 8.0.4,
`NCCL` 2.8 / 2.12, `NVHPC` 22.7, `magma` 2.5.4.

## Software (modules)

Orion uses Lmod with EasyBuild-built modules on the shared filesystem (~321
distinct module names as of this snapshot). Load them **inside** the job script,
after `module purge`, since the login-node environment does not propagate to
compute nodes. Common categories: compilers (`GCC`, Intel oneAPI), MPI
(`OpenMPI`), BLAS/LAPACK (`OpenBLAS`, MKL), languages (`Python`, `R`, `Julia`),
bioinformatics (`BLAST+`, `BWA`, `SAMtools`, `BCFtools`, `GATK`, `STAR`, …),
`CUDA`, and `Apptainer` for containers.

For Python/R packages not packaged as a module, use a per-user environment via
`module load Miniforge3` (micromamba) — see `../SKILL.md` and the Orion wiki's
*Conda environments* page.

## SLURM configuration

Orion runs **SLURM 24.11.0** (`sinfo --version`). Key settings
(`scontrol show config`, snapshot 2026-06-29):

| Setting | Value | What it means for you |
|---------|-------|-----------------------|
| `ClusterName` | `orion` | |
| `SelectType` | `select/cons_tres` (`CR_CORE_MEMORY`) | jobs are allocated by **core + memory** — set both `-c`/`--cpus` and `--mem` |
| `SchedulerType` | `sched/backfill` | accurate, modest `--time`/`--mem` lets your job backfill ahead of big ones and start sooner |
| `PriorityType` | `priority/multifactor` | fair-share dominates (`PriorityWeightFairShare=1000000` vs age/jobsize 10000, partition 100000); heavy recent usage lowers priority, decaying with a **14-day half-life** |
| `PreemptMode` | `OFF` | running jobs are never preempted or requeued out from under you |
| `TaskPlugin` / `ProctrackType` | `task/cgroup,task/affinity` / `proctrack/cgroup` | every job is **cgroup-confined**: you cannot use more cores/RAM/GPU than allocated. Threads beyond `-c` oversubscribe your cores (slower, not more); RAM over `--mem` is OOM-killed; all child processes are tracked and cleaned up — nothing escapes the job |
| `PrologFlags` | `Alloc,Contain` | each job gets a private, auto-cleaned `$TMPDIR` and process namespace on the node |
| `TmpFS` | `/work/users` | node-local scratch root (the NVMe SSD); your auto-cleaned per-job `$TMPDIR` lives under here — stage I/O-heavy work in `$TMPDIR`, not over NFS |
| `JobRequeue` | 1 | a `NODE_FAIL` (or `scontrol requeue`) **auto-resubmits** the job from scratch — make work idempotent/checkpointed, or pass `--no-requeue` if a rerun would corrupt output |
| `DefMemPerCPU` | 3000 MB | memory per core if you omit `--mem` |
| `MaxArraySize` / `MaxJobCount` / `MaxStepCount` | 200000 / 500000 / 40000 | array-index and queue ceilings — far above normal use |
| `GresTypes` | `gpu` | GPUs are the only *requestable* generic resource (`--gpus N`); `gres/gpumem` and `gres/gpuutil` are **accounted** (not requested), so `jobinfo`/`sacct` report GPU memory and utilization |
| `MailProg` / `JobSubmitPlugins` | `/usr/bin/mail` / none | `--mail-type` works (incl. `TIME_LIMIT_80`, `ARRAY_TASKS`); nothing silently rewrites your submit request — what you ask is what you get |
| `AccountingStorageType` | `slurmdbd` | `sacct` / `jobinfo` / `sstat` accounting works |
| `KillOnBadExit` | 0 | a failing step doesn't auto-kill the job; the job template captures and returns the real exit code itself |

Partitions: `orion` is the default; **no default walltime** (`DefaultTime=NONE`, so always pass `--time`), `MaxTime=UNLIMITED`, `OverSubscribe=NO` (cores are yours exclusively). QOS `normal` has priority 0 and **no hard caps** (no `MaxWall`/`MaxJobs`/`MaxTRES`) — the real limits are the soft etiquette ones in `safety.md`. The GPU partition's billing is weighted (`TRESBillingWeights=cpu=1.0,gres/gpu=24.0`): **one GPU costs the same as 24 CPU cores**, and the full node bills `552` (384 cores + 7×24). Request only the GPUs you use.

**Checkpoint on timeout.** Because `MaxTime=UNLIMITED` but long jobs still risk node events, have `--time`-bounded work save state before SLURM kills it: `#SBATCH --signal=B:USR1@120` delivers `SIGUSR1` to the batch step 120 s before the walltime, so a trap can checkpoint and exit cleanly (then resume via `--chunks`). This is the graceful-shutdown counterpart to the resume-from-checkpoint requirement on array/chunked jobs.

## Interactive jobs

Never run work on the login node (it kills anything over 5 minutes). For an interactive shell on a compute node:

**`qlogin`** — the Orion wrapper around `salloc` + `srun --pty`. It defaults to an 11-hour walltime and starts a **login shell**, so `module` and micromamba are ready. Pass any Slurm options through:

```bash
qlogin -c 8 --mem 16g                      # CPU shell on the orion partition
qlogin -p GPU --gpus 1 -c 8 --mem 32g      # GPU shell on gn-41
qlogin -c 4 --mem 8g -t 2:00:00            # override the 11 h default
```

You land on the node; `exit` releases the allocation. Good for compiling, debugging, building/testing an environment, or a quick `nvidia-smi`.

**Raw Slurm** for full control:

```bash
srun -p GPU --account nmbu --gpus 1 -c 8 --mem 32g -t 1:00:00 --pty bash -l
salloc -p orion -c 8 --mem 16g -t 2:00:00        # hold an allocation, attach steps
```

**Open OnDemand** (`https://apps.orion.nmbu.no`) gives browser-based Jupyter, RStudio, a desktop, and a terminal, each launched as a Slurm job — the no-terminal path.

This skill itself drives **batch** jobs over SSH; interactive sessions are run directly (above), not through the wrappers.

## Cost & overflow

Orion's cost model is being finalized (rates not yet published) — contact
orion-support@nmbu.no for budget estimates or usage questions. The habits that
lower billing also shorten queue time: right-size with `jobinfo`, prefer `--mem`
over `--mem-per-cpu`, use `$TMPDIR` for I/O, compress and delete old data. If a
project needs far more CPU-hours than Orion allows, apply for national
infrastructure via **Sigma2** — its cluster *Saga* uses the same Slurm workflow,
so scripts (and this skill) mostly transfer by repointing `hpc.env`.

## Recovering deleted files (snapshots)

`$HOME`, `$PROJECTS`, `$SCRATCH`, `$LABFILES`, and `$COURSES` are snapshotted
(read-only, GPFS/Spectrum Scale). `$TMPDIR` is never backed up, and `$SCRATCH`
snapshots do not survive its 180-day purge — important results belong in
`$PROJECTS`.

Snapshots live in a hidden **`.snapshots/`** directory at the **root of each
filesystem** (not inside individual project/user folders), with point-in-time
subdirectories named `@GMT-YYYY.MM.DD-HH.MM.SS` (daily around 22:00, plus weekly
retention; typically a few days to a few weeks back). Verified roots:

```bash
ls /mnt/users/.snapshots      # $HOME filesystem
ls /mnt/project/.snapshots    # $PROJECTS
ls /mnt/SCRATCH/.snapshots    # $SCRATCH
```

Inside a snapshot the full tree is reproduced, so restore by copying your file
back out (snapshots are read-only):

```bash
# recover a project file from the 16 June snapshot:
cp /mnt/project/.snapshots/@GMT-2026.06.16-22.00.57/<group>/<you>/lost.txt \
   /mnt/project/<group>/<you>/
```

This pairs with the never-`--delete` rule: an accidental delete or overwrite
under `HPC_REMOTE_ROOT` is usually recoverable from the latest snapshot that
still holds the file. If it predates all snapshots, email orion-support@nmbu.no.
