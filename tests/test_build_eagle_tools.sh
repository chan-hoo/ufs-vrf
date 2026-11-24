#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ufs-vrf-eagle-test.XXXXXXXX")"
test_dir="$(cd "$test_dir" && pwd -P)"
root="$test_dir/sorc"
bin="$test_dir/bin"
env_dir="$root/conda/envs/plot"
log="$test_dir/conda.log"

cleanup() {
    rm -f "$bin/uname" "$root/eagle-tools/pyproject.toml" "$root/plot.yaml" \
        "$root/condarc" "$root/activate_wxvx.sh" "$root/activate_plot.sh" \
        "$root/activate_mdt.sh" "$root/conda/bin/conda" \
        "$root/conda/etc/profile.d/conda.sh" "$env_dir/bin/python" \
        "$env_dir/bin/uw" "$env_dir/bin/eagle-tools" "$log" "$test_dir/error"
    rmdir "$env_dir/bin" "$env_dir" "$root/conda/envs" "$root/conda/pkgs" \
        "$root/conda/cache" "$root/conda/etc/profile.d" "$root/conda/etc" \
        "$root/conda/bin" "$root/conda" "$root/eagle-tools" "$root" "$bin" "$test_dir" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$bin" "$root/eagle-tools" "$root/conda/bin" \
    "$root/conda/etc/profile.d" "$env_dir/bin"
touch "$root/eagle-tools/pyproject.toml" "$root/plot.yaml" "$root/conda/bin/conda"
chmod +x "$root/conda/bin/conda"
printf '#!/usr/bin/env bash\necho "python test"\n' > "$env_dir/bin/python"
chmod +x "$env_dir/bin/python"

cat > "$bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac
EOF
chmod +x "$bin/uname"

cat > "$root/conda/etc/profile.d/conda.sh" <<'EOF'
conda() {
    printf '%s\n' "$*" >> "$TEST_LOG"
    case "$1" in
        --version|info|list) ;;
        env)
            [[ "$2" == create && "$3" == --prefix && "$4" == "$EXPECTED_ENV" ]]
            mkdir -p "$4/bin"
            printf '#!/usr/bin/env bash\necho "python test"\n' > "$4/bin/python"
            printf '#!/usr/bin/env bash\necho "uw test"\n' > "$4/bin/uw"
            chmod +x "$4/bin/python" "$4/bin/uw"
            ;;
        run)
            [[ "$2" == --prefix && "$3" == "$EXPECTED_ENV" ]]
            shift 3
            if [[ "$*" == "python -m pip install $TEST_ROOT/eagle-tools" ]]; then
                [[ "${FAIL_INSTALL:-0}" == 0 ]] || return 1
                printf '#!/usr/bin/env bash\necho "eagle-tools test"\n' > "$EXPECTED_ENV/bin/eagle-tools"
                chmod +x "$EXPECTED_ENV/bin/eagle-tools"
            fi
            "$EXPECTED_ENV/bin/$1" "${@:2}"
            ;;
        *) echo "Unexpected conda command: $*" >&2; return 1 ;;
    esac
}
EOF

export PATH="$bin:$PATH" TEST_ROOT="$root" TEST_LOG="$log" EXPECTED_ENV="$env_dir"
cd "$root"

# Existing and newly created plot environments both install and verify the source.
for state in existing new; do
    if [[ "$state" == new ]]; then
        rm "$env_dir/bin/python" "$env_dir/bin/eagle-tools"
        rmdir "$env_dir/bin" "$env_dir"
    fi
    : > "$log"
    bash "$repo_root/sorc/build_ufsvrf.sh" plot --refresh
    grep -Fxq "run --prefix $env_dir python -m pip install $root/eagle-tools" "$log"
    grep -Fxq "run --prefix $env_dir python -m pip install --no-deps --force-reinstall $root/eagle-tools" "$log"
    grep -Fxq "run --prefix $env_dir eagle-tools --help" "$log"
done

: > "$log"
if FAIL_INSTALL=1 bash "$repo_root/sorc/build_ufsvrf.sh" plot --refresh; then
    echo "Expected eagle-tools installation to fail" >&2
    exit 1
fi
if grep -Fq "eagle-tools --help" "$log"; then
    echo "Verified eagle-tools after a failed installation" >&2
    exit 1
fi

rm "$root/eagle-tools/pyproject.toml"
: > "$log"
if bash "$repo_root/sorc/build_ufsvrf.sh" plot 2>"$test_dir/error"; then
    echo "Expected an uninitialized eagle-tools submodule to fail" >&2
    exit 1
fi
grep -Fq "git submodule update --init --recursive" "$test_dir/error"
[[ ! -s "$log" ]]
