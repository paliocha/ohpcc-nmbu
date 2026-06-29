# Troubleshooting (Orion)

Diagnose a job by symptom. Most answers come from three commands — run them first:

```bash
ssh orion 'squeue -u $USER'                # is it pending/running, and why (REASON column)
ssh orion 'jobinfo <jobid>'                # friendly per-job summary + efficiency (seff is broken)
ssh orion 'sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,MaxRSS,ReqMem'
bash scripts/hpc_fetch.sh slurm_logs/      # pull <jobid>.out / .err down to read locally
```

## Can't connect / push / submit

| Symptom | Cause / fix |
|---------|-------------|
| `Connection refused` / `No route to host` | Off-campus without VPN. Connect the NMBU VPN. |
| `Permission denied (publickey,password)` | Wrong username, or account not active yet. Check `~/.ssh/config`; email orion-support. |
| `Host key verification failed` | Host key changed. `ssh-keygen -R login.orion.nmbu.no` (or `filemanager.orion.nmbu.no`), reconnect, accept. |
| push/submit hangs or re-prompts | SSH socket isn't warm or multiplexing isn't configured. `bash scripts/hpc_login.sh`; see `ssh_setup.md`. |
| Logged in then instantly disconnected | `$HOME` is full (200–300 GB quota). Check `myquota`; free space. |
| `refusing to operate outside HPC_REMOTE_ROOT` | A path escaped the root, or `HPC_REMOTE_ROOT` is mistyped. Fix `hpc.env`. |
| transfer dies after ~5 min | You used the login host for data. Set `HPC_TRANSFER_HOST=orion-filemanager`. |

## Job won't start — read the `squeue` REASON

| REASON | Meaning |
|--------|---------|
| `Priority` | Others are ahead (fair-share). Wait. |
| `Resources` | Not enough free CPU/RAM/GPU right now. Wait, or ask for less. |
| `ReqNodeNotAvail` | Targeted node is down/reserved. Drop the constraint. |
| `QOSMax...` / `AssocMax...` | Hit a soft cap. Cancel some jobs or wait. |
| `BadConstraints` | A `--gres`/`--constraint` matches no node. Check `sinfo -o "%n %G"`. |
| `JobHeldUser` | You held it. `ssh orion scontrol release <jobid>`. |

## Job died — match the State / exit code

| State / output | Cause |
|----------------|-------|
| `TIMEOUT` | Hit `--time`. Increase it, checkpoint, or use `--chunks`. |
| `OUT_OF_MEMORY`, or `FAILED` `ExitCode 137` | Hit `--mem` (OOM-killed). Increase `--mem`. |
| `FAILED` `ExitCode 1` (or other non-zero) | Your program errored. Read `<jobid>.err` / `.out`. |
| `NODE_FAIL` | The node went down. Resubmit. |
| `CANCELLED by <uid>` | Team Orion cancelled it — check your email. |

## Job is slow

- Low CPU efficiency in `jobinfo` and the work should be parallel → your software isn't using the cores it asked for. See `cluster-overview.md` (parallelism is single-node OpenMP unless the tool is MPI-linked: `ldd <prog> | grep -i 'mpi\|cuda\|omp'`).
- I/O-bound (many small files over NFS) → stage to node-local `$TMPDIR`, then copy results back.
- `MaxRSS` near `ReqMem` → swapping; raise `--mem`.

## Environment / modules

- `module` not found in a job: it *is* available in Orion job shells; if a script disabled it, `source /etc/profile.d/z00_lmod.sh`.
- Tool missing: `module spider <name>` / `module avail`; if absent, request it (wiki *Request software*) or install via micromamba.
- `micromamba activate` fails with "env not found": the env was created under a different `MAMBA_ROOT_PREFIX` than the job uses. Keep the root consistent (default `~/micromamba`).

## Recover a deleted/overwritten file

From read-only filesystem snapshots — see `cluster-overview.md` (Recovering deleted files): `ls /mnt/project/.snapshots`, then `cp` the file back out.

## When to email orion-support@nmbu.no

After trying the above, include: what happened, the **job ID**, the time, what you tried, and the output of `jobinfo <jobid>` plus the relevant lines from `<jobid>.out`/`.err`. A specific report is handled in hours; "my job doesn't work" is not.
