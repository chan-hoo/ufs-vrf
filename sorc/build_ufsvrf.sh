#!/usr/bin/env bash

set -euo pipefail

# ==============================================================
# Define installation directories
# ==============================================================

INSTALL_ROOT="$(pwd -P)"
INSTALLDIR="$INSTALL_ROOT/conda"

export CONDA_PKGS_DIRS="$INSTALLDIR/pkgs"
export CONDA_ENVS_PATH="$INSTALLDIR/envs"
export XDG_CACHE_HOME="$INSTALLDIR/cache"

WXVX_ENV="$CONDA_ENVS_PATH/wxvx"
PLOT_ENV="$CONDA_ENVS_PATH/plot"
MDT_ENV="$CONDA_ENVS_PATH/mdt"

echo "Installation root: $INSTALL_ROOT"
echo "Miniforge:         $INSTALLDIR"
echo "Package cache:     $CONDA_PKGS_DIRS"
echo "Environment path:  $CONDA_ENVS_PATH"

# ==============================================================
# Select environments to build
# ==============================================================

usage() {
    echo "Usage: $0 [wxvx|plot|mdt|all] [--rebuild]" >&2
    echo "  No argument: Build all environments, prompting before replacing existing ones" >&2
    echo "  --rebuild: Remove and recreate selected environments without prompting" >&2
}

SELECTION="all"
REBUILD=false
SELECTION_SET=false
PROMPT_EXISTING=false
if (( $# == 0 )); then
    PROMPT_EXISTING=true
fi

for arg in "$@"; do
    case "$arg" in
        wxvx|plot|mdt|all)
            if [[ "$SELECTION_SET" == true ]]; then
                echo "Error: Specify only one environment selection." >&2
                usage
                exit 1
            fi
            SELECTION="$arg"
            SELECTION_SET=true
            ;;
        --rebuild)
            if [[ "$REBUILD" == true ]]; then
                echo "Error: --rebuild was specified more than once." >&2
                usage
                exit 1
            fi
            REBUILD=true
            ;;
        *)
            echo "Error: Invalid argument: $arg" >&2
            usage
            exit 1
            ;;
    esac
done

case "$SELECTION" in
    wxvx)
        ENVIRONMENTS=("wxvx")
        ;;
    plot)
        ENVIRONMENTS=("plot")
        ;;
    mdt)
        ENVIRONMENTS=("mdt")
        ;;
    all)
        ENVIRONMENTS=("wxvx" "plot" "mdt")
        ;;
esac

if [[ " ${ENVIRONMENTS[*]} " == *" wxvx "* ]] &&
    [[ ! -f "$INSTALL_ROOT/wxvx/recipe/meta.yaml" || ! -f "$INSTALL_ROOT/wxvx/src/wxvx/resources/info.json" ]]; then
    echo "Error: wxvx submodule is not initialized in $INSTALL_ROOT/wxvx." >&2
    echo "Run 'git submodule update --init --recursive' and try again." >&2
    exit 1
fi

if [[ " ${ENVIRONMENTS[*]} " == *" wxvx "* || " ${ENVIRONMENTS[*]} " == *" plot "* ]] &&
    [[ ! -f "$INSTALL_ROOT/eagle-tools/pyproject.toml" ]]; then
    echo "Error: eagle-tools submodule is not initialized in $INSTALL_ROOT/eagle-tools." >&2
    echo "Run 'git submodule update --init --recursive' and try again." >&2
    exit 1
fi

if [[ " ${ENVIRONMENTS[*]} " == *" mdt "* ]] &&
    [[ ! -f "$INSTALL_ROOT/mdt/pyproject.toml" || ! -f "$INSTALL_ROOT/mdt/uv.lock" ]]; then
    echo "Error: MDT submodule is not initialized in $INSTALL_ROOT/mdt." >&2
    echo "Run 'git submodule update --init --recursive' and try again." >&2
    exit 1
fi

for ENV_NAME in "${ENVIRONMENTS[@]}"; do
    if [[ ! -f "$INSTALL_ROOT/${ENV_NAME}.yaml" ]]; then
        echo "Error: Environment YAML not found: $INSTALL_ROOT/${ENV_NAME}.yaml" >&2
        exit 1
    fi
done

# ==============================================================
# Detect architecture
# ==============================================================

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)
        ARCH="x86_64"
        ;;
    Linux-aarch64)
        ARCH="aarch64"
        ;;
    *)
        echo "Error: Unsupported operating system or architecture:"
        echo "       $(uname -s)-$(uname -m)"
        exit 1
        ;;
esac

echo "Architecture:      $ARCH"

EXISTING_ENVIRONMENTS=()
for ENV_NAME in "${ENVIRONMENTS[@]}"; do
    ENV_PREFIX="$CONDA_ENVS_PATH/$ENV_NAME"
    if [[ -x "$ENV_PREFIX/bin/python" ]]; then
        EXISTING_ENVIRONMENTS+=("$ENV_NAME")
    elif [[ -e "$ENV_PREFIX" ]]; then
        echo "Error: $ENV_PREFIX exists but does not appear to be a valid Python environment." >&2
        echo "Please inspect the directory before proceeding." >&2
        exit 1
    fi
done

if [[ "$PROMPT_EXISTING" == true ]] && (( ${#EXISTING_ENVIRONMENTS[@]} > 0 )); then
    echo "Existing environments: ${EXISTING_ENVIRONMENTS[*]}"
    echo "Rebuilding removes these environments and any packages added to them."
    if ! read -r -p "Remove and rebuild them? (Y/N) " answer; then
        echo "Error: No answer received; use --rebuild to rebuild without prompting." >&2
        exit 1
    fi
    case "$answer" in
        y|Y|yes|YES|Yes) REBUILD=true ;;
        n|N|no|NO|No) echo "Build cancelled; no environments were removed."; exit 0 ;;
        *) echo "Error: Please answer Y or N; no environments were removed." >&2; exit 1 ;;
    esac
fi

if [[ "$REBUILD" == true ]] && (( ${#EXISTING_ENVIRONMENTS[@]} > 0 )); then
    for ENV_NAME in "${EXISTING_ENVIRONMENTS[@]}"; do
        ENV_PREFIX="$CONDA_ENVS_PATH/$ENV_NAME"
        if [[ "${CONDA_PREFIX:-}" == "$ENV_PREFIX" ]]; then
            echo "Error: $ENV_PREFIX is active. Deactivate it before rebuilding." >&2
            exit 1
        fi
    done
fi

# ==============================================================
# Install Miniforge locally
# ==============================================================

MINIFORGE_VERSION="26.1.1-3"
INSTALLER="Miniforge3-${MINIFORGE_VERSION}-Linux-${ARCH}.sh"

INSTALLER_URL="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${INSTALLER}"

if [[ -x "$INSTALLDIR/bin/conda" ]]; then
    echo "Found existing Miniforge installation: $INSTALLDIR"
else
    if [[ -e "$INSTALLDIR" ]]; then
        echo "Error: $INSTALLDIR exists but is not a valid Miniforge installation." >&2
        echo "Please inspect the directory before proceeding." >&2
        exit 1
    fi

    mkdir -p "$INSTALL_ROOT"

    echo "Downloading Miniforge ${MINIFORGE_VERSION}..."

    if command -v wget >/dev/null 2>&1; then
        wget -O "$INSTALL_ROOT/$INSTALLER" "$INSTALLER_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -fL "$INSTALLER_URL" -o "$INSTALL_ROOT/$INSTALLER"
    else
        echo "Error: Neither wget nor curl is available." >&2
        exit 1
    fi

    echo "Installing Miniforge into $INSTALLDIR..."

    bash "$INSTALL_ROOT/$INSTALLER" -bfp "$INSTALLDIR"

    rm -f "$INSTALL_ROOT/$INSTALLER"
fi

# ==============================================================
# Configure local Conda directories
# ==============================================================

mkdir -p "$CONDA_PKGS_DIRS"
mkdir -p "$CONDA_ENVS_PATH"
mkdir -p "$XDG_CACHE_HOME"

# Use a project-local Conda configuration.
export CONDARC="$INSTALL_ROOT/condarc"

cat > "$CONDARC" <<EOF
channels:
  - conda-forge

envs_dirs:
  - $CONDA_ENVS_PATH

pkgs_dirs:
  - $CONDA_PKGS_DIRS

register_envs: false
EOF

# ==============================================================
# Initialize Conda without conda init
# ==============================================================

source "$INSTALLDIR/etc/profile.d/conda.sh"

echo
echo "Conda version:"
conda --version

echo
echo "Effective Conda configuration:"
conda info

sync_mdt() {
    (
        source "$INSTALLDIR/etc/profile.d/conda.sh"
        conda activate "$MDT_ENV"
        cd "$INSTALL_ROOT/mdt"
        UV_PROJECT_ENVIRONMENT="$MDT_ENV" uv sync --no-active --frozen --extra prefect --extra dask --inexact
    )
}

sync_wxvx() {
    local channel="$INSTALLDIR/wxvx-channel"
    local spec

    if [[ ! -x "$INSTALLDIR/bin/conda-build" ]]; then
        conda install --yes --prefix "$INSTALLDIR" --override-channels -c conda-forge conda-build
    fi

    mkdir -p "$channel"
    conda build "$INSTALL_ROOT/wxvx/recipe" \
        --no-test --no-anaconda-upload --output-folder "$channel" \
        --override-channels -c conda-forge -c ufs-community
    conda index "$channel"

    spec=$("$INSTALLDIR/bin/python" -c '
import json
import sys
with open(sys.argv[1]) as f:
    info = json.load(f)
print("wxvx={}=py_{}".format(info["version"], info["buildnum"]))
' "$INSTALL_ROOT/wxvx/src/wxvx/resources/info.json")
    conda install --yes --prefix "$WXVX_ENV" --force-reinstall \
        --override-channels -c "$channel" -c conda-forge -c ufs-community -c oar-gsl \
        "file://$channel::$spec"
    conda run --prefix "$WXVX_ENV" wxvx --version
}

sync_eagle_tools() {
    local env_prefix="$1"
    local source="$INSTALL_ROOT/eagle-tools"

    # Resolve dependencies first, then refresh only the source package even if
    # its version is unchanged, without forcing a reinstall of its dependencies.
    conda run --prefix "$env_prefix" python -m pip install "$source"
    conda run --prefix "$env_prefix" python -m pip install --no-deps --force-reinstall "$source"
    conda run --prefix "$env_prefix" eagle-tools --help
}

# ==============================================================
# Build selected Python environments
# ==============================================================

for ENV_NAME in "${ENVIRONMENTS[@]}"; do

    echo
    echo "=============================================================="
    echo "Processing environment: $ENV_NAME"
    echo "=============================================================="

    ENV_FILE="$INSTALL_ROOT/${ENV_NAME}.yaml"
    ENV_PREFIX="$CONDA_ENVS_PATH/$ENV_NAME"

    # ----------------------------------------------------------
    # Rebuild or update existing environments
    # ----------------------------------------------------------

    if [[ -x "$ENV_PREFIX/bin/python" ]]; then
        echo "Found existing environment: $ENV_PREFIX"
        if [[ "$REBUILD" == true ]]; then
            echo "Removing environment: $ENV_PREFIX"
            conda env remove --yes --prefix "$ENV_PREFIX"
        else
            if [[ "$ENV_NAME" == "wxvx" ]]; then
                echo "Building and installing wxvx from the submodule."
                sync_wxvx
            elif [[ "$ENV_NAME" == "mdt" ]]; then
                echo "Synchronizing and verifying MDT."
                sync_mdt
                conda run --prefix "$ENV_PREFIX" mdt --version
            fi
            if [[ "$ENV_NAME" != "mdt" ]]; then
                echo "Installing eagle-tools from the submodule."
                sync_eagle_tools "$ENV_PREFIX"
            fi
            continue
        fi
    fi

    if [[ -e "$ENV_PREFIX" ]]; then
        echo "Error: $ENV_PREFIX exists but does not appear to be a valid Python environment." >&2
        echo "Please inspect the directory before proceeding." >&2
        exit 1
    fi

    # ----------------------------------------------------------
    # Create environment from YAML
    # ----------------------------------------------------------

    echo "Creating $ENV_NAME environment from:"
    echo "  $ENV_FILE"

    conda env create \
        --prefix "$ENV_PREFIX" \
        --file "$ENV_FILE"

    if [[ "$ENV_NAME" == "wxvx" ]]; then
        sync_wxvx
    elif [[ "$ENV_NAME" == "mdt" ]]; then
        sync_mdt
    fi
    if [[ "$ENV_NAME" != "mdt" ]]; then
        sync_eagle_tools "$ENV_PREFIX"
    fi

    # ----------------------------------------------------------
    # Verify installation
    # ----------------------------------------------------------

    echo
    echo "Verifying $ENV_NAME environment..."

    conda run --prefix "$ENV_PREFIX" python --version
    conda run --prefix "$ENV_PREFIX" python -m pip --version

    if [[ "$ENV_NAME" == "mdt" ]]; then
        conda run --prefix "$ENV_PREFIX" mdt --version
    fi

    if [[ "$ENV_NAME" != "mdt" ]]; then
        conda run --prefix "$ENV_PREFIX" uw --version
    fi

    echo
    echo "Installed packages in $ENV_NAME:"
    conda list --prefix "$ENV_PREFIX"

    echo
    echo "Environment completed successfully: $ENV_PREFIX"

done

# ==============================================================
# Create activation scripts
# ==============================================================

cat > "$INSTALL_ROOT/activate_wxvx.sh" <<EOF
#!/usr/bin/env bash

# Activate the locally installed wxvx environment.
# Source this script; do not execute it.

_CONDA_ROOT="$INSTALLDIR"
_WXVX_ENV="\$_CONDA_ROOT/envs/wxvx"

if [[ ! -f "\$_CONDA_ROOT/etc/profile.d/conda.sh" ]]; then
    echo "Error: Local Miniforge installation not found: \$_CONDA_ROOT" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -d "\$_WXVX_ENV" ]]; then
    echo "Error: wxvx environment not found: \$_WXVX_ENV" >&2
    return 1 2>/dev/null || exit 1
fi

source "\$_CONDA_ROOT/etc/profile.d/conda.sh"
conda activate "\$_WXVX_ENV"

conda list | grep -E 'wxvx|metplus|uwtools|eagle-tools'
EOF

cat > "$INSTALL_ROOT/activate_plot.sh" <<EOF
#!/usr/bin/env bash

# Activate the locally installed plot environment.
# Source this script; do not execute it.

_CONDA_ROOT="$INSTALLDIR"
_PLOT_ENV="\$_CONDA_ROOT/envs/plot"

if [[ ! -f "\$_CONDA_ROOT/etc/profile.d/conda.sh" ]]; then
    echo "Error: Local Miniforge installation not found: \$_CONDA_ROOT" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -d "\$_PLOT_ENV" ]]; then
    echo "Error: plot environment not found: \$_PLOT_ENV" >&2
    return 1 2>/dev/null || exit 1
fi

source "\$_CONDA_ROOT/etc/profile.d/conda.sh"
conda activate "\$_PLOT_ENV"

conda list | grep -E 'cartopy|matplotlib|numpy|pandas|uwtools|eagle-tools'
EOF

cat > "$INSTALL_ROOT/activate_mdt.sh" <<EOF
#!/usr/bin/env bash

# Activate the locally installed MDT environment.
# Source this script; do not execute it.

_CONDA_ROOT="$INSTALLDIR"
_MDT_ENV="\$_CONDA_ROOT/envs/mdt"

if [[ ! -f "\$_CONDA_ROOT/etc/profile.d/conda.sh" ]]; then
    echo "Error: Local Miniforge installation not found: \$_CONDA_ROOT" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -d "\$_MDT_ENV" ]]; then
    echo "Error: MDT environment not found: \$_MDT_ENV" >&2
    return 1 2>/dev/null || exit 1
fi

source "\$_CONDA_ROOT/etc/profile.d/conda.sh"
conda activate "\$_MDT_ENV"

mdt --version
EOF

chmod +x "$INSTALL_ROOT/activate_wxvx.sh"
chmod +x "$INSTALL_ROOT/activate_plot.sh"
chmod +x "$INSTALL_ROOT/activate_mdt.sh"

echo
echo "=============================================================="
echo "Build process completed successfully."
echo "=============================================================="

echo "Miniforge:          $INSTALLDIR"
echo "wxvx environment:   $WXVX_ENV"
echo "plot environment:   $PLOT_ENV"
echo "MDT environment:    $MDT_ENV"
echo "Package cache:      $CONDA_PKGS_DIRS"
echo "Conda config:       $CONDARC"
echo
echo "Activation scripts:"
echo "  source ./activate_wxvx.sh"
echo "  source ./activate_plot.sh"
echo "  source ./activate_mdt.sh"
