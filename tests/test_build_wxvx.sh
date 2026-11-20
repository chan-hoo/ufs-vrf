#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ufs-vrf-wxvx-test.XXXXXXXX")"
test_dir="$(cd "$test_dir" && pwd -P)"
root="$test_dir/sorc"
bin="$test_dir/bin"
env_dir="$root/conda/envs/wxvx"
log="$test_dir/conda.log"

cleanup() {
    rm -f "$bin/uname" "$root/wxvx/recipe/meta.yaml" \
        "$root/wxvx/src/wxvx/resources/info.json" "$root/wxvx.yaml" \
        "$root/condarc" "$root/activate_wxvx.sh" "$root/activate_plot.sh" \
        "$root/activate_mdt.sh" "$root/conda/bin/conda" "$root/conda/bin/conda-build" \
        "$root/conda/bin/python" "$root/conda/etc/profile.d/conda.sh" \
        "$env_dir/bin/python" "$env_dir/bin/wxvx" "$env_dir/bin/uw" "$log" "$test_dir/error"
    rmdir "$env_dir/bin" "$env_dir" "$root/conda/envs" "$root/conda/pkgs" \
        "$root/conda/cache" "$root/conda/wxvx-channel" "$root/conda/etc/profile.d" \
        "$root/conda/etc" "$root/conda/bin" "$root/conda" \
        "$root/wxvx/recipe" "$root/wxvx/src/wxvx/resources" "$root/wxvx/src/wxvx" \
        "$root/wxvx/src" "$root/wxvx" "$root" "$bin" "$test_dir" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$bin" "$root/wxvx/recipe" "$root/wxvx/src/wxvx/resources" \
    "$root/conda/bin" "$root/conda/etc/profile.d" "$env_dir/bin"
touch "$root/wxvx/recipe/meta.yaml" "$root/wxvx.yaml" "$root/conda/bin/conda"
printf '{"version":"0.8.1","buildnum":"0"}\n' > "$root/wxvx/src/wxvx/resources/info.json"
printf '#!/usr/bin/env bash\nexec python3 "$@"\n' > "$root/conda/bin/python"
printf '#!/usr/bin/env bash\necho "python test"\n' > "$env_dir/bin/python"
chmod +x "$root/conda/bin/conda" "$root/conda/bin/python" "$env_dir/bin/python"

cat > "$bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac
EOF
chmod +x "$bin/uname"

cat > "$root/conda/etc/profile.d/conda.sh" <<'EOF'
conda() {
    printf '%s\n' "$*" >> "$TEST_LOG"
    case "$1" in
        --version|info|list|index) ;;
        build)
            [[ "$2" == "$TEST_ROOT/wxvx/recipe" ]]
            [[ "$*" == *"--no-test --no-anaconda-upload"* ]]
            [[ "${FAIL_BUILD:-0}" == 0 ]]
            ;;
        install)
            if [[ "$*" == *"--prefix $TEST_ROOT/conda --override-channels"* ]]; then
                touch "$TEST_ROOT/conda/bin/conda-build"
                chmod +x "$TEST_ROOT/conda/bin/conda-build"
            else
                [[ "$*" == *"--prefix $EXPECTED_WXVX_ENV --force-reinstall"* ]]
                [[ "$*" == *"file://$TEST_ROOT/conda/wxvx-channel::wxvx=0.8.1=py_0"* ]]
                printf '#!/usr/bin/env bash\necho "wxvx test"\n' > "$EXPECTED_WXVX_ENV/bin/wxvx"
                chmod +x "$EXPECTED_WXVX_ENV/bin/wxvx"
            fi
            ;;
        env)
            [[ "$2" == create && "$3" == --prefix && "$4" == "$EXPECTED_WXVX_ENV" ]]
            mkdir -p "$4/bin"
            printf '#!/usr/bin/env bash\necho "python test"\n' > "$4/bin/python"
            printf '#!/usr/bin/env bash\necho "uw test"\n' > "$4/bin/uw"
            chmod +x "$4/bin/python" "$4/bin/uw"
            ;;
        run)
            [[ "$2" == --prefix && "$3" == "$EXPECTED_WXVX_ENV" ]]
            local prefix="$3"
            shift 3
            "$prefix/bin/$1" "${@:2}"
            ;;
        *) echo "Unexpected conda command: $*" >&2; return 1 ;;
    esac
}
EOF

export PATH="$bin:$PATH" TEST_ROOT="$root" TEST_LOG="$log" EXPECTED_WXVX_ENV="$env_dir"
cd "$root"

# An existing environment must be updated, not skipped.
bash "$repo_root/sorc/build_ufsvrf.sh" wxvx
grep -Fq "file://$root/conda/wxvx-channel::wxvx=0.8.1=py_0" "$log"
[[ -x "$env_dir/bin/wxvx" ]]

# A new environment also receives the locally built package.
rm "$env_dir/bin/python" "$env_dir/bin/wxvx"
rmdir "$env_dir/bin" "$env_dir"
: > "$log"
bash "$repo_root/sorc/build_ufsvrf.sh" wxvx
grep -Fq "env create --prefix $env_dir" "$log"
grep -Fq "file://$root/conda/wxvx-channel::wxvx=0.8.1=py_0" "$log"

# Build failures must not proceed to installation.
: > "$log"
if FAIL_BUILD=1 bash "$repo_root/sorc/build_ufsvrf.sh" wxvx; then
    echo "Expected wxvx build to fail" >&2
    exit 1
fi
if grep -Fq "file://$root/conda/wxvx-channel::wxvx=" "$log"; then
    echo "Installed wxvx after a failed build" >&2
    exit 1
fi

# Fail early with an actionable message for an uninitialized submodule.
rm "$root/wxvx/recipe/meta.yaml"
if bash "$repo_root/sorc/build_ufsvrf.sh" wxvx 2>"$test_dir/error"; then
    echo "Expected an uninitialized submodule to fail" >&2
    exit 1
fi
grep -Fq "git submodule update --init --recursive" "$test_dir/error"
