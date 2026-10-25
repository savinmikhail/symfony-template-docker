#!/bin/sh
# Shared polling-loop policy: finish active work, interrupt interval sleeps,
# and never start the next command after TERM/INT. Docker bounds stuck work.
worker_shutdown=0
worker_child=""
worker_sleeping=0

worker_request_shutdown() {
  worker_shutdown=1
  if [ "$worker_sleeping" -eq 1 ] && [ -n "$worker_child" ]; then
    # A timer can inherit the shell trap before exec; TERM can be swallowed.
    # Discard only this stateless sleep, never an active business command.
    kill -KILL "$worker_child" 2>/dev/null || true
  fi
}
trap worker_request_shutdown TERM INT

worker_wait() {
  while :; do
    if wait "$worker_child" 2>/dev/null; then worker_status=0; else worker_status=$?; fi
    if [ "$worker_shutdown" -eq 1 ] && kill -0 "$worker_child" 2>/dev/null; then
      continue
    fi
    break
  done
  worker_child=""
  worker_sleeping=0
  return "$worker_status"
}

worker_run() {
  [ "$worker_shutdown" -eq 0 ] || return 0
  "$@" &
  worker_child=$!
  worker_sleeping=0
  worker_wait
}

worker_sleep() {
  [ "$worker_shutdown" -eq 0 ] || return 0
  sleep "$1" &
  worker_child=$!
  worker_sleeping=1
  if [ "$worker_shutdown" -eq 1 ]; then kill -KILL "$worker_child" 2>/dev/null || true; fi
  worker_wait || true
}
