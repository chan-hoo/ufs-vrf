#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ufs-vrf-rebuild-test.XXXXXXXX")"
test_dir="$(cd "$test_dir" && pwd -P)"
root="$test_dir/sorc"
bin="$test_dir/bin"
log="$test_dir/conda.log"

cleanup() {
    for env in wxvx plot mdt; do
        rm -f "$root/conda/envs/$env/bin/python" "$root/$env.yaml"
        rmdir "$root/conda/envs/$env/bin" "$root/conda/envs/$env" 2>/dev/null || true
    done
    rm -f "$bin/uname" "$bin/uv" "$root/wxvx/recipe/meta.yaml" \
        "$root/wxvx/src/wxvx/resources/info.json" "$root/eagle-tools/pyproject.toml" \
        "$root/mdt/pyproject.toml" "$root/mdt/uv.lock" "$root/condarc" \
        "$root/activate_wxvx.sh" "$root/activate_plot.sh" "$root/activate_mdt.sh" \
        "$root/conda/bin/conda" "$root/conda/bin/conda-build" "$root/conda/bin/python" \
        "$root/conda/etc/profile.d/conda.sh" "$log" "$test_dir/output" "$test_dir/error"
    rmdir "$root/conda/envs" "$root/conda/pkgs" "$root/conda/cache" \
        "$root/conda/wxvx-channel" "$root/conda/etc/profile.d" "$root/conda/etc" \
        "$root/conda/bin" "$root/conda" "$root/wxvx/recipe" \
        "$root/wxvx/src/wxvx/resources" "$root/wxvx/src/wxvx" "$root/wxvx/src" \
        "$root/wxvx" "$root/eagle-tools" "$root/mdt" "$root" "$bin" "$test_dir" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$bin" "$root/wxvx/recipe" "$root/wxvx/src/wxvx/resources" \
    "$root/eagle-tools" "$root/mdt" "$root/conda/bin" "$root/conda/etc/profile.d"
touch "$root/wxvx/recipe/meta.yaml" "$root/eagle-tools/pyproject.toml" \
    "$root/mdt/pyproject.toml" "$root/mdt/uv.lock" \
    "$root/wxvx.yaml" "$root/plot.yaml" "$root/mdt.yaml" \
    "$root/conda/bin/conda" "$root/conda/bin/conda-build"
printf '{"version":"0.8.1","buildnum":"0"}\n' > "$root/wxvx/src/wxvx/resources/info.json"
printf '#!/usr/bin/env bash\nexec python3 "$@"\n' > "$root/conda/bin/python"
chmod +x "$root/conda/bin/conda" "$root/conda/bin/conda-build" "$root/conda/bin/python"

cat > "$bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac
EOF
cat > "$bin/uv" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin/uname" "$bin/uv"

cat > "$root/conda/etc/profile.d/conda.sh" <<'EOF'
conda() {
    printf '%s\n' "$*" >> "$TEST_LOG"
    case "$1" in
        --version|info|list|index|build|install|run|activate) ;;
        env)
            case "$2" in
                remove)
                    [[ "$3" == --yes && "$4" == --prefix ]]
                    [[ "${FAIL_REMOVE:-0}" == 0 ]] || return 1
                    rm "$5/bin/python"
                    rmdir "$5/bin" "$5"
                    ;;
                create)
                    [[ "$3" == --prefix && "$5" == --file ]]
                    mkdir -p "$4/bin"
                    printf '#!/usr/bin/env bash\nexit 0\n' > "$4/bin/python"
                    chmod +x "$4/bin/python"
                    ;;
                *) return 1 ;;
            esac
            ;;
        *) echo "Unexpected conda command: $*" >&2; return 1 ;;
    esac
}
EOF

export PATH="$bin:$PATH" TEST_LOG="$log"
cd "$root"

# A fresh noninteractive install does not prompt, including with --rebuild.
bash "$repo_root/sorc/build_ufsvrf.sh" --rebuild </dev/null > "$test_dir/output"
for env in wxvx plot mdt; do
    grep -Fq "env create --prefix $root/conda/envs/$env" "$log"
done
if grep -Fq "env remove" "$log"; then
    echo "Removed an environment during a fresh install" >&2
    exit 1
fi

# Cancellation and missing input must leave all environments untouched.
for answer in N eof invalid; do
    : > "$log"
    case "$answer" in
        N) printf 'N\n' | bash "$repo_root/sorc/build_ufsvrf.sh" > "$test_dir/output" ;;
        eof)
            if bash "$repo_root/sorc/build_ufsvrf.sh" </dev/null > "$test_dir/output" 2>"$test_dir/error"; then
                echo "Expected missing confirmation to fail" >&2
                exit 1
            fi
            grep -Fq "No answer received" "$test_dir/error"
            ;;
        invalid)
            if printf 'maybe\n' | bash "$repo_root/sorc/build_ufsvrf.sh" > "$test_dir/output" 2>"$test_dir/error"; then
                echo "Expected invalid confirmation to fail" >&2
                exit 1
            fi
            ;;
    esac
    [[ ! -s "$log" ]]
    for env in wxvx plot mdt; do [[ -x "$root/conda/envs/$env/bin/python" ]]; done
done

# A selected rebuild removes and recreates only that environment.
: > "$log"
bash "$repo_root/sorc/build_ufsvrf.sh" wxvx --rebuild > "$test_dir/output"
grep -Fxq "env remove --yes --prefix $root/conda/envs/wxvx" "$log"
grep -Fq "env create --prefix $root/conda/envs/wxvx" "$log"
if grep -Eq 'env (remove|create).*envs/(plot|mdt)' "$log"; then
    echo "Changed an unselected environment" >&2
    exit 1
fi

# Confirmation and --rebuild both recreate all existing environments.
for mode in prompt flag; do
    : > "$log"
    if [[ "$mode" == prompt ]]; then
        printf 'Y\n' | bash "$repo_root/sorc/build_ufsvrf.sh" > "$test_dir/output"
    else
        bash "$repo_root/sorc/build_ufsvrf.sh" --rebuild > "$test_dir/output"
    fi
    for env in wxvx plot mdt; do
        grep -Fxq "env remove --yes --prefix $root/conda/envs/$env" "$log"
        grep -Fq "env create --prefix $root/conda/envs/$env" "$log"
    done
done

# Detect an active environment or missing input before removing anything.
for failure in active missing-yaml; do
    : > "$log"
    if [[ "$failure" == active ]]; then
        if CONDA_PREFIX="$root/conda/envs/mdt" bash "$repo_root/sorc/build_ufsvrf.sh" --rebuild > "$test_dir/output" 2>"$test_dir/error"; then
            echo "Expected an active environment to prevent rebuilding" >&2
            exit 1
        fi
        grep -Fq "Deactivate it before rebuilding" "$test_dir/error"
    else
        rm "$root/mdt.yaml"
        if bash "$repo_root/sorc/build_ufsvrf.sh" --rebuild > "$test_dir/output" 2>"$test_dir/error"; then
            echo "Expected a missing YAML to prevent rebuilding" >&2
            exit 1
        fi
        touch "$root/mdt.yaml"
    fi
    [[ ! -s "$log" ]]
done

# A failed removal must not create a replacement.
: > "$log"
if FAIL_REMOVE=1 bash "$repo_root/sorc/build_ufsvrf.sh" plot --rebuild > "$test_dir/output" 2>"$test_dir/error"; then
    echo "Expected failed removal to stop the build" >&2
    exit 1
fi
if grep -Fq "env create" "$log"; then
    echo "Created an environment after removal failed" >&2
    exit 1
fi

# Confirmation also handles a mix of existing and missing environments.
rm "$root/conda/envs/plot/bin/python"
rmdir "$root/conda/envs/plot/bin" "$root/conda/envs/plot"
: > "$log"
printf 'y\n' | bash "$repo_root/sorc/build_ufsvrf.sh" > "$test_dir/output"
grep -Fq "env create --prefix $root/conda/envs/plot" "$log"
if grep -Fq "env remove --yes --prefix $root/conda/envs/plot" "$log"; then
    echo "Removed a missing environment" >&2
    exit 1
fi
for env in wxvx mdt; do
    grep -Fxq "env remove --yes --prefix $root/conda/envs/$env" "$log"
    grep -Fq "env create --prefix $root/conda/envs/$env" "$log"
done

# Reject ambiguous argument combinations before doing any work.
for args in 'wxvx plot' '--rebuild --rebuild' '--unknown'; do
    : > "$log"
    # Intentional splitting supplies multiple arguments to the script.
    if bash "$repo_root/sorc/build_ufsvrf.sh" $args > "$test_dir/output" 2>"$test_dir/error"; then
        echo "Expected invalid arguments to fail: $args" >&2
        exit 1
    fi
    [[ ! -s "$log" ]]
done
