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
