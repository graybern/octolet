#!/usr/bin/env bash
set -euo pipefail

# BlinkStick ad-hoc control via privileged pods + nsenter
# Uses the host's /opt/venvs/tools/bin/blinkstick CLI directly
#
# Physical left-to-right order (verified 2026-09-30):
#   control-2 → control-3 → worker-1 → worker-2

NODES=(octolet-control-2 octolet-control-3 octolet-worker-1 octolet-worker-2)

COLOR="${COLOR:-green}"
DURATION="${DURATION:-3600}"
MODE="${MODE:-sweep}"
ON_TIME="${ON_TIME:-0.4}"
CYCLE_TIME="${CYCLE_TIME:-2.0}"

usage() {
  cat <<EOF
Usage: $0 [sweep|solid|off|pulse]

Modes:
  sweep   Left-to-right chase pattern (default)
  solid   All nodes solid color
  pulse   All nodes slow pulse (on/off)
  off     Turn all off and clean up pods

Environment variables:
  COLOR=green       CSS color name or hex (default: green)
  DURATION=3600     Seconds to run (default: 1 hour)
  ON_TIME=0.4       Seconds LED stays on per beat (sweep mode)
  CYCLE_TIME=2.0    Seconds per full sweep cycle

Examples:
  task blinkstick:sweep
  task blinkstick:solid COLOR=red
  COLOR=blue DURATION=600 task blinkstick:sweep
  task blinkstick:off
EOF
  exit 1
}

cleanup() {
  echo "Cleaning up blinkstick pods..."
  for node in "${NODES[@]}"; do
    kubectl delete pod "blink-${node}" --force --grace-period=0 2>/dev/null &
  done
  wait
  echo "Done"
}

launch_pod() {
  local node=$1
  local script=$2

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: blink-${node}
  namespace: default
  labels:
    app: blinkstick-adhoc
spec:
  nodeName: ${node}
  restartPolicy: Never
  hostPID: true
  containers:
  - name: blink
    image: alpine:3.20
    command: ["sh", "-c"]
    args:
    - |
${script}
    securityContext:
      privileged: true
    volumeMounts:
    - name: dev
      mountPath: /dev
  volumes:
  - name: dev
    hostPath:
      path: /dev
EOF
}

do_off() {
  cleanup
  # Send off command to each node via a quick pod
  for node in "${NODES[@]}"; do
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: blink-${node}
  namespace: default
spec:
  nodeName: ${node}
  restartPolicy: Never
  hostPID: true
  containers:
  - name: blink
    image: alpine:3.20
    command: ["sh", "-c"]
    args: ["nsenter -t 1 -m -u -i -n -p -- /opt/venvs/tools/bin/blinkstick --set-color off 2>/dev/null; echo done"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: dev
      mountPath: /dev
  volumes:
  - name: dev
    hostPath:
      path: /dev
EOF
  done
  sleep 5
  cleanup
}

do_sweep() {
  cleanup
  local start=$(($(date +%s) + 15))
  local off_time
  off_time=$(echo "${CYCLE_TIME} - ${ON_TIME}" | bc)

  echo "Sweep: ${COLOR}, cycle=${CYCLE_TIME}s, on=${ON_TIME}s, duration=${DURATION}s"
  echo "Physical order: ${NODES[*]}"
  echo "Syncing to wall clock: ${start}"

  for i in 0 1 2 3; do
    local node="${NODES[$i]}"
    local init_delay
    init_delay=$(echo "$i * ${ON_TIME} * 1.25" | bc)
    local script
    script=$(cat <<SCRIPT
      BS="/opt/venvs/tools/bin/blinkstick"
      START_AT=${start}
      while [ \$(date +%s) -lt \$START_AT ]; do sleep 0.1; done
      sleep ${init_delay}
      END=\$((START_AT + ${DURATION}))
      while [ \$(date +%s) -lt \$END ]; do
        nsenter -t 1 -m -u -i -n -p -- \$BS --set-color ${COLOR} 2>/dev/null
        sleep ${ON_TIME}
        nsenter -t 1 -m -u -i -n -p -- \$BS --set-color off 2>/dev/null
        sleep ${off_time}
      done
      nsenter -t 1 -m -u -i -n -p -- \$BS --set-color off 2>/dev/null
SCRIPT
)
    launch_pod "$node" "$script"
  done
  echo "Running for ${DURATION}s — use 'task blinkstick:off' to stop early"
}

do_solid() {
  cleanup
  echo "Solid: ${COLOR} for ${DURATION}s on all nodes"

  for node in "${NODES[@]}"; do
    local script
    script=$(cat <<SCRIPT
      BS="/opt/venvs/tools/bin/blinkstick"
      nsenter -t 1 -m -u -i -n -p -- \$BS --set-color ${COLOR} 2>/dev/null
      END=\$(($(date +%s) + ${DURATION}))
      while [ \$(date +%s) -lt \$END ]; do sleep 10; done
      nsenter -t 1 -m -u -i -n -p -- \$BS --set-color off 2>/dev/null
SCRIPT
)
    launch_pod "$node" "$script"
  done
  echo "Running for ${DURATION}s — use 'task blinkstick:off' to stop early"
}

do_pulse() {
  cleanup
  echo "Pulse: ${COLOR}, 2s on / 1s off for ${DURATION}s on all nodes"

  for node in "${NODES[@]}"; do
    local script
    script=$(cat <<SCRIPT
      BS="/opt/venvs/tools/bin/blinkstick"
      END=\$(($(date +%s) + ${DURATION}))
      while [ \$(date +%s) -lt \$END ]; do
        nsenter -t 1 -m -u -i -n -p -- \$BS --set-color ${COLOR} 2>/dev/null
        sleep 2
        nsenter -t 1 -m -u -i -n -p -- \$BS --set-color off 2>/dev/null
        sleep 1
      done
      nsenter -t 1 -m -u -i -n -p -- \$BS --set-color off 2>/dev/null
SCRIPT
)
    launch_pod "$node" "$script"
  done
  echo "Running for ${DURATION}s — use 'task blinkstick:off' to stop early"
}

case "${1:-${MODE}}" in
  sweep)  do_sweep ;;
  solid)  do_solid ;;
  pulse)  do_pulse ;;
  off)    do_off ;;
  *)      usage ;;
esac
