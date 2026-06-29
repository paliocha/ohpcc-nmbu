#!/bin/bash
# Warm up the SSH ControlMaster socket to the cluster. Run once per session;
# the socket persists per ControlPersist in ~/.ssh/config (12 h per ControlPersist),
# and every subsequent ssh/rsync/scp reuses it and skips the OTP/SSO prompt.
#
# THE HUMAN TYPES THE OTP, NOT THE ASSISTANT. If a socket is already alive this
# exits immediately without prompting — always run it (or `ssh -O check`) before
# asking the user to authenticate.
#
# Usage: bash hpc_login.sh [-c hpc.env]
set -euo pipefail
. "$(dirname "$0")/_hpc_lib.sh"
if [ "${1:-}" = "-c" ] || [ "${1:-}" = "--config" ]; then
    [ -n "${2:-}" ] || hpc_die "$1 needs a path to an hpc.env file"
    export HPC_CONFIG="$2"; shift 2
fi
hpc_load_config
hpc_check_ssh_multiplexing || true   # warn-only; never blocks a login attempt

hosts="$HPC_HOST"
[ "$HPC_TRANSFER_HOST" != "$HPC_HOST" ] && hosts="$hosts $HPC_TRANSFER_HOST"

rc=0
for h in $hosts; do
    if ssh -O check "$h" 2>/dev/null; then
        echo "ssh master socket to $h already alive."
        hpc_audit hpc_login_reuse --host "$h" --exit 0
        continue
    fi
    echo "Opening ssh master socket to $h (type your credential at the prompt if asked)..."
    hrc=0
    ssh "$h" true || hrc=$?
    hpc_audit hpc_login_open --host "$h" --exit "$hrc"
    [ "$hrc" -ne 0 ] && rc="$hrc"
done
exit "$rc"
