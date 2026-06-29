# Hard safety rules (Orion HPC, NMBU)

Orion is shared infrastructure. These rules are non-negotiable; the wrappers
encode them. Authoritative policy: the Orion wiki at <https://orion.nmbu.no/>
(Partitions, File systems, Policies). Figures current as of June 2026.

1. **Never run compute on the login node — always `sbatch`.** `login.orion.nmbu.no`
   is for editing, submitting jobs, and checking queue/storage state only; it
   auto-kills any command over 5 minutes. Heavy work goes through SLURM
   (`hpc_submit.py`). Large data transfers go through the file-transfer host
   `filemanager.orion.nmbu.no` (`HPC_TRANSFER_HOST`), not the login node.
2. **All remote writes are confined to `HPC_REMOTE_ROOT`.** `hpc_push.sh`/
   `hpc_fetch.sh` refuse any destination outside it (`..` traversal + shell
   metacharacters rejected); `hpc_submit.py` guards `--name`/`--remote-subdir`.
   The first push/submit verifies over SSH that the root is owned by you.
3. **`rsync` never uses `--delete`.** The wrappers never pass it. Push still
   *overwrites* a differing remote file — preview with `--dry-run`, or set
   `HPC_PUSH_BACKUP=1`.
4. **No personal/sensitive/GDPR data on Orion.** Orion does not store or support
   analysis of personal sensitive data (medical records, anything identifying a
   living individual). See the Policies page.
5. **Right-size and be a good neighbour.** Always set `--time` (no default
   walltime). After a run, check `seff <jobid>` (CPU/memory efficiency) and drop
   over-requested cores/memory next time. Don't hold idle GPUs. Don't sustain
   more than ~150 CPUs concurrently for >1 day without emailing
   orion-support@nmbu.no first. `$SCRATCH` is purged after 180 days — move
   keepers to `$PROJECTS`. Compress raw data (`pigz`).
6. **Every action is logged.** Wrappers append one JSON line per action to
   `.hpc_audit.log` (gitignored); the SLURM job appends `job_start`/`job_end`
   to a remote `audit.remote.log` that `hpc_fetch.sh` merges back. The log
   records intent/outcome only — never stdout/stderr. Inspect: `jq . .hpc_audit.log`.
7. **Enforcement is opt-in (defense in depth).** Enable the PreToolUse hook
   (`scripts/hpc_guard_hook.py`) so the harness blocks raw `ssh rm -rf` /
   `rsync --delete` against either Orion host. Setup is in SKILL.md.

Off-campus access requires the NMBU Check Point VPN — Orion is not on the public
internet. Email rate limit: NMBU caps outbound mail at ~200/day, so array jobs
are clamped to `--mail-type FAIL`.
