#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ufs-vrf-mdt-test.XXXXXXXX")"
root="$test_dir/sorc"
bin="$test_dir/bin"
env_dir="$root/conda/envs/mdt"

cleanup() {
    rm -f "$bin/uname" "$bin/uv" "$root/mdt/pyproject.toml" "$root/mdt/uv.lock" \
        "$root/mdt.yaml" "$root/condarc" "$root/activate_wxvx.sh" \
        "$root/activate_plot.sh" "$root/activate_mdt.sh" \
        "$root/conda/bin/conda" "$root/conda/etc/profile.d/conda.sh" \
        "$env_dir/bin/python" "$env_dir/bin/mdt"
    rmdir "$env_dir/bin" "$env_dir" "$root/conda/envs" "$root/conda/pkgs" \
        "$root/conda/cache" "$root/conda/etc/profile.d" "$root/conda/etc" \
        "$root/conda/bin" "$root/conda" "$root/mdt" "$root" "$bin" "$test_dir" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$bin" "$root/mdt" "$root/conda/bin" "$root/conda/etc/profile.d" "$env_dir/bin"
touch "$root/mdt/pyproject.toml" "$root/mdt/uv.lock" "$root/mdt.yaml" "$root/conda/bin/conda"
chmod +x "$root/conda/bin/conda"

cat > "$bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac
EOF
cat > "$bin/uv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$UV_PROJECT_ENVIRONMENT" == "$EXPECTED_MDT_ENV" ]]
[[ "$*" == "sync --no-active --frozen --extra prefect --extra dask --inexact" ]]
[[ "$VIRTUAL_ENV" == "/unrelated/virtualenv" ]]
printf '#!/usr/bin/env bash\necho "mdt test"\n' > "$EXPECTED_MDT_ENV/bin/mdt"
chmod +x "$EXPECTED_MDT_ENV/bin/mdt"
EOF
chmod +x "$bin/uname" "$bin/uv"

cat > "$root/conda/etc/profile.d/conda.sh" <<'EOF'
conda() {
    case "$1" in
        --version|info|list) ;;
        activate) export CONDA_PREFIX="$2" ;;
        env)
            [[ "$2" == create && "$3" == --prefix ]]
            mkdir -p "$4/bin"
            printf '#!/usr/bin/env bash\necho "python test"\n' > "$4/bin/python"
            chmod +x "$4/bin/python"
            ;;
        run)
            [[ "$2" == --prefix && "$3" == "$EXPECTED_MDT_ENV" ]]
            local prefix="$3"
            shift 3
            "$prefix/bin/$@"
            ;;
        *) echo "Unexpected conda command: $*" >&2; return 1 ;;
    esac
}
EOF
printf '#!/usr/bin/env bash\necho "python test"\n' > "$env_dir/bin/python"
chmod +x "$env_dir/bin/python"

export PATH="$bin:$PATH"
export EXPECTED_MDT_ENV="$env_dir"
export VIRTUAL_ENV="/unrelated/virtualenv"
export UV_PROJECT_ENVIRONMENT="/unrelated/project"

cd "$root"
bash "$repo_root/sorc/build_ufsvrf.sh" mdt --refresh
rm "$env_dir/bin/python" "$env_dir/bin/mdt"
rmdir "$env_dir/bin" "$env_dir"
bash "$repo_root/sorc/build_ufsvrf.sh" mdt
