#!/usr/bin/env bash
set -euo pipefail

# SSH tunnel management for vmnode852 WinRM access.
# Creates a local port forward: localhost:15852 → vmnode852.bcis.bates.edu:5986

TUNNEL_HOST="xoxd-bates"
LOCAL_PORT=15852
REMOTE_HOST="vmnode852.bcis.bates.edu"
REMOTE_PORT=5986
PID_FILE="/tmp/forkbomb-demo-tunnel.pid"

usage() {
    echo "Usage: $0 {start|stop|status|check}"
    echo ""
    echo "  start   - Start SSH tunnel (localhost:${LOCAL_PORT} → ${REMOTE_HOST}:${REMOTE_PORT})"
    echo "  stop    - Stop SSH tunnel"
    echo "  status  - Show tunnel status"
    echo "  check   - Check if tunnel is functional (test WinRM port)"
    exit 1
}

start_tunnel() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Tunnel already running (PID $(cat "$PID_FILE"))"
        return 0
    fi

    echo "Starting SSH tunnel: localhost:${LOCAL_PORT} → ${REMOTE_HOST}:${REMOTE_PORT} via ${TUNNEL_HOST}"
    ssh -f -N \
        -L "${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}" \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        "${TUNNEL_HOST}"

    # Find the PID of the tunnel process
    local pid
    pid=$(pgrep -f "ssh.*-L.*${LOCAL_PORT}:${REMOTE_HOST}" | head -1)

    if [ -n "$pid" ]; then
        echo "$pid" > "$PID_FILE"
        echo "Tunnel started (PID ${pid})"
    else
        echo "ERROR: Tunnel process not found after start"
        return 1
    fi
}

stop_tunnel() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo "Tunnel stopped (PID ${pid})"
        else
            echo "Tunnel process ${pid} not running"
        fi
        rm -f "$PID_FILE"
    else
        echo "No tunnel PID file found"
        # Try to find and kill by pattern
        local pid
        pid=$(pgrep -f "ssh.*-L.*${LOCAL_PORT}:${REMOTE_HOST}" | head -1)
        if [ -n "$pid" ]; then
            kill "$pid"
            echo "Found and stopped orphaned tunnel (PID ${pid})"
        fi
    fi
}

check_status() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Tunnel is RUNNING (PID $(cat "$PID_FILE"))"
        echo "  Local:  localhost:${LOCAL_PORT}"
        echo "  Remote: ${REMOTE_HOST}:${REMOTE_PORT}"
        echo "  Via:    ${TUNNEL_HOST}"
        return 0
    else
        echo "Tunnel is NOT running"
        return 1
    fi
}

check_connectivity() {
    echo "Testing WinRM port connectivity on localhost:${LOCAL_PORT}..."
    if nc -z -w5 localhost "${LOCAL_PORT}" 2>/dev/null; then
        echo "Port ${LOCAL_PORT} is REACHABLE"
    else
        echo "Port ${LOCAL_PORT} is NOT reachable"
        echo "Is the tunnel running? Try: $0 start"
        return 1
    fi
}

case "${1:-}" in
    start)  start_tunnel ;;
    stop)   stop_tunnel ;;
    status) check_status ;;
    check)  check_connectivity ;;
    *)      usage ;;
esac
