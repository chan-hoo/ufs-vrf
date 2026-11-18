#!/usr/bin/env bash

set -xue

ulimit -s unlimited; ulimit -a;

# Load the shared YAML utility.
source "${USHufsvrf}/yaml_utils.sh"
config_common="${exp_case_path}/configs/config_common.yaml"

# Read common configuration values.
external_data=$(read_yaml "${config_common}" "external_data_vx_grid2prcp")
external_data=$(printf '%s' "${external_data}" | tr '[:upper:]' '[:lower:]')
platform=$(read_yaml "${config_common}" "platform")
run_type=$(read_yaml "${config_common}" "run_type")
truth_prcp_model=$(read_yaml "${config_common}" "truth_prcp_model")
workflow_type=$(read_yaml "${config_common}" "workflow_type")

# Copy pre-downloaded data files for c-test to temporary working directory.
if [[ "${run_type}" == "ctest" ]]; then
  # Truth data
  if [[ "${external_data}" == "false" ]]; then
    mkdir -p ${DATA}/grids
    cp -rp "${FIXufsvrf}/data_${platform}/ctest/${workflow_type}/truth_grids/${truth_grid_model}/truth" ${DATA}/grids/.
  fi
fi

# Copy pre-processed forecast data if needed.
if [[ "${workflow_type}" == "eagle" ]]; then
  ## Fallback data
  fallback_prewxvx="${FIXufsvrf}/data_${platform}/ctest/${workflow_type}/post_prewxvx"
  if [[ -d "${COMIN}/post_prewxvx" ]] && [[ -n "$(ls -A "${COMIN}/post_prewxvx")" ]]; then
    cp -rp "${COMIN}/post_prewxvx" "${DATA}/."
    echo "Using prewxvx results from ${COMIN}/post_prewxvx"
  elif [[ -d "${fallback_prewxvx}" ]] && [[ -n "$(ls -A "${fallback_prewxvx}")" ]]; then
    cp -rp "${fallback_prewxvx}" "${DATA}/."
    echo "Using prewxvx results from ${fallback_prewxvx}"
  else
    err_exit "No valid prewxvx results directory found."
  fi
fi

# Update configuration file with temporary working directory.
config_fn="config_vx_grid2prcp.yaml"
config_content=$(<"${exp_case_path}/configs/${config_fn}")
printf '%s\n' "${config_content//'{{ DATA }}'/${DATA}}" > "${DATA}/${config_fn}"

# Run wxvx.
export pgm="wxvx"

. prep_step
time ${pgm} -c ${config_fn} -t plots -f
export err=$?; err_chk
if [[ $err != 0 ]]; then
  err_exit "wxvx: vx_grid2prcp failed"
fi

# Copy result files/directories to COMOUT
cp -rp ${DATA}/plots ${COMOUT}/grid2prcp_plots
cp -rp ${DATA}/stats grid2prcp_stats
find grid2prcp_stats -type f ! \( -name "*.stat" -o -name "*_pairs.nc" -o -name "*.txt" \) -delete
cp -rp grid2prcp_stats ${COMOUT}/
