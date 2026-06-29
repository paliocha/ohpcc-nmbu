# SSH setup (one-time, per machine)

The skill assumes SSH aliases with connection multiplexing so transfers are fast
and prompt-free. Orion uses your NMBU username + password; if you set up an SSH
key there is no password prompt at all. Add these blocks to `~/.ssh/config`.

## Orion

```
Host orion
	Hostname login.orion.nmbu.no
	User <your-nmbu-username>
	ControlMaster auto
	ControlPath ~/.ssh/cm-%r@%h:%p
	ControlPersist 12h
	ServerAliveInterval 60
	ServerAliveCountMax 3

Host orion-filemanager
	Hostname filemanager.orion.nmbu.no
	User <your-nmbu-username>
	ControlMaster auto
	ControlPath ~/.ssh/cm-%r@%h:%p
	ControlPersist 12h
	ServerAliveInterval 60
	ServerAliveCountMax 3
```

Set `HPC_HOST=orion` and `HPC_TRANSFER_HOST=orion-filemanager` in `hpc.env`.

- **Two hosts on purpose.** `login.orion.nmbu.no` is a shell + job-submission
  host that kills commands over 5 minutes. `filemanager.orion.nmbu.no` is the
  data pipe with no time limit; both share the same filesystems. `hpc_login.sh`
  warms a socket to both.
- **Off-campus needs the NMBU Check Point VPN** — Orion is not on the public
  internet. Connect the VPN first, then SSH works as if on campus.
- **known_hosts conflict on the file manager.** If you see
  "REMOTE HOST IDENTIFICATION HAS CHANGED" for `filemanager.orion.nmbu.no`, clear
  the stale entry and accept the new key:
  ```
  ssh-keygen -R filemanager.orion.nmbu.no
  ssh orion-filemanager true
  ```
- **Interactive paths (out of scope).** Open OnDemand (`apps.orion.nmbu.no`) and
  `qlogin` give browser/interactive compute sessions. This skill is for batch
  jobs; use those directly when you want a notebook or an interactive shell.

## Other SLURM clusters

Any cluster reachable by plain SSH works: add a `Host` block with the
multiplexing options and point `HPC_HOST` at it. Leave `HPC_TRANSFER_HOST` unset
to reuse it. Set `HPC_ACCOUNT`, `HPC_PARTITION`, `HPC_REMOTE_ROOT` to match.
