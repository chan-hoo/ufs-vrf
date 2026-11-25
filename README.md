# Unified Forecast System Verification Framework (UFS-VRF)

UFS-VRF provides a framework for configuring and running weather verification
for Unified Forecast System (UFS) applications, including Global Workflow,
EAGLE, and RRFS, on NOAA RDHPCS platforms. It brings together wxvx, MDT, and
supporting tools ([user's guide](https://wxvx4ufs.readthedocs.io/en/latest/index.html)).

## 1. Build and Installation

### Step 1. Clone the repository

Choose one of the following methods to clone the repository.

- SSH (if you have configured an SSH key for GitHub):
```bash
git clone --recurse-submodules git@github.com:chan-hoo/ufs-vrf.git
```

- HTTPS:
```bash
git clone --recurse-submodules https://github.com/chan-hoo/ufs-vrf.git
```

If you already cloned the repository without submodules, initialize them with:
```bash
git submodule update --init --recursive
```

### Step 2. Run the installation script

```bash
cd ufs-vrf/sorc
./build_ufsvrf.sh
```

By default, the script builds the `wxvx`, `plot`, and `mdt` environments. To
build only one environment, pass `wxvx`, `plot`, or `mdt` as an argument.

The script asks before removing and rebuilding any selected existing
environments, including when one is named. Answer `N` to cancel. To rebuild without prompting, run
`./build_ufsvrf.sh --rebuild` for all environments or, for example,
`./build_ufsvrf.sh wxvx --rebuild` for one. Rebuilding removes packages added
to the selected environments; deactivate an active environment first. Miniforge
and its cache are retained. Use `--refresh` instead to refresh source packages
without recreating existing environments or reapplying their YAML.

wxvx is built from the pinned `sorc/wxvx` submodule using its Conda recipe.
Rerun `./build_ufsvrf.sh wxvx --refresh` after updating the submodule to rebuild and
install it into the wxvx environment. The build installs `conda-build` into
the local Miniforge installation and requires access to the Conda channels.

eagle-tools is installed with pip from the pinned `sorc/eagle-tools` submodule
into both the wxvx and plot environments. Rerun `./build_ufsvrf.sh wxvx --refresh`
and `./build_ufsvrf.sh plot --refresh` after updating it to refresh both installations.

MDT is installed from the pinned `sorc/mdt` submodule using its committed
`uv.lock`. Its environment is separate from the existing wxvx and plotting
environments. If an earlier MDT installation failed, rerun
`./build_ufsvrf.sh mdt --refresh` from `sorc` to synchronize the existing environment.

## 2. Activate the wxvx Environment

After installation, activate the environment by sourcing the activation script:

```bash
source activate_wxvx.sh
```

## 3. Configuration

The configuration YAML files and set-up script are located in the `parm` directory:

```bash
cd ufs-vrf/parm
```

The main configuration files are:
- `config_base.yaml`: Define the basic configuration parameters
- `config_platform.yaml`: Define the platform-specific configuration parameters

Copy the sample configuration file for EAGLE ctest:
```bash
cp config_samples/config_base_eagle_gfs_ctest.yaml config.yaml
```

Before proceeding, review the parameters `account` ,`exp_case_name`, and `platform`.

```bash
vim config.yaml
```
- Available options:
  - `forecast_type`: eagle, hrrrcast, global_workflow
  - `platform`: ursa, hercules, gaea-c6, orion, derecho
  - `run_type`: ctest
  - `truth_grid_model`: GFS, HRRR
  - `truth_obs_model`: PREPBUFR
  - `truth_prcp_model`: STAGEIV
  - `workflow_manager`: ecflow, None

Run the set-up script to generate the experimental case configuration and supporting directories:

```bash
./setup.py --config config.yaml
```

By default, the script generates the `exp_cases` and `PTMP` directories under the `parm` directory.

## 4. Job Submission

### ecFlow option (`app.workflow_manager: ecflow`)

Load module(s) for ecFlow:

- On Ursa / Derecho:

```bash
module load ecflow/5.11.4
```

- On Hercules / Orion / Gaea-C6:

```bash
cd ..
module use modulefiles
module load modules_[hercules/orion/gaea-c6]
```

Start the ecFlow server if necessary:

```bash
cd parm/exp_cases/[app.exp_case_name]/ecf
./start_server.sh
```

Begin the case-specific ecFlow suite:

```bash
./begin_suite.sh
```

Open the ecFlow GUI:

```bash
ecflow_ui &
```
Note that the ecFlow GUI does not work correctly on Gaea-C6.

Stop the ecFlow server once all workflow tasks are complete:

```bash
./stop_server.sh
```

###  Manual submission of job cards (`app.workflow_manager: None`)

Navigate to the job cards directory for your experimental case:

```bash
cd exp_cases/[app.exp_case_name]/job_cards
```

Submit the desired task:

- Slurm (Ursa / Hercules / Orion / Gaea-C6):

```bash
sbatch jufsvrf_[task_name]
```

- PBS pro (Derecho):

```bash
qsub jufsvrf_[task_name]
```

## 5. Results and Log Files

After the job completes, check the following directories for output files and execution logs:
- `com_dir`: symlink to the directory containing the result files
- `log_dir`: symlink to the directory containing the log files
- `tmp_dir`: symlink to the directory containing the working directories

