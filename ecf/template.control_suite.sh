#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 --suspend | --resume | --kill | --halt | --restart | --status | --requeue | --show | --free"
  exit 1
fi
ACTION="$1"

if [ -z "${ECF_HOST}" ]; then
  export ECF_HOST=$(hostname)
fi
if [ -z "${ECF_PORT}" ]; then
  export ECF_PORT=$(( $(id -u) + 1500 ))
fi
export ECF_HOME="{{ exp_ecf_path }}"
export ECF_SUITE="{{ exp_case_name }}"

echo "ECF_HOME: ${ECF_HOME}"
echo "ECF_PORT: ${ECF_PORT}"
echo "ECF_HOST: ${ECF_HOST}"
echo "ECF_SUITE: ${ECF_SUITE}"

if [ "${ACTION}" = "--suspend" ]; then
  # Suspend the given node. This prevents job generation for the given node, or any child node.
  echo "Suspend suite ${ECF_SUITE} ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --suspend "/${ECF_SUITE}"
elif [ "${ACTION}" = "--resume" ]; then
  # Resume the given node. This allows job generation for the given node, or any child node.
  echo "Resume suite ${ECF_SUITE} ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --resume "/${ECF_SUITE}"
elif [ "${ACTION}" = "--kill" ]; then
  # Kills the job associated with the node.
  echo "Kill suite ${ECF_SUITE} ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --kill "/${ECF_SUITE}"
########## Server control ##########
elif [ "${ACTION}" = "--halt" ]; then
  # Stop server communication with jobs, and new job scheduling.
  echo "Halt server ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --halt=yes
elif [ "${ACTION}" = "--restart" ]; then
  # Start job scheduling, communication with jobs, and respond to all requests.
  echo "Restart server ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --restart
########## Status and information ##########
elif [ "${ACTION}" = "--status" ]; then
  # Check the status of the suite and display its state tree
  echo "Status of suite ${ECF_SUITE} ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --get_state "/${ECF_SUITE}"
elif [ "${ACTION}" = "--show" ]; then
  # Display the full definition tree of the suite
  echo "Show suite definition ${ECF_SUITE} ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --get "/${ECF_SUITE}"
elif [ "${ACTION}" = "--requeue" ]; then
  # Requeue the suite/node. This will clear task completion status and re-enable jobs
  echo "Requeue suite ${ECF_SUITE} ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --requeue "/${ECF_SUITE}"
elif [ "${ACTION}" = "--free" ]; then
  # Reset node status when task is NOT running (e.g., after external task failure)
  echo "Free (reset) suite ${ECF_SUITE} ..."
  ecflow_client --port="${ECF_PORT}" --host="${ECF_HOST}" --free "/${ECF_SUITE}"
else
  echo "FATAL ERROR: ${ACTION} is NOT supported in this script. Please check --help"
  ecflow_client --help=summary
  exit 2
fi
