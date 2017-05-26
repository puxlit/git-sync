#!/bin/sh -eux

# Define trivial helper functions.
error() { echo "$@" >&2; }
eager_and() (
    [ -z "${__ea_exit_status+x}" ] && [ -z "${__ea_cmd+x}" ] || exit 3

    __ea_exit_status=0
    for __ea_cmd in "$@"; do ${__ea_cmd} || __ea_exit_status=1; done
    return ${__ea_exit_status}
)
trace_exec() (
    [ "${-#*e}" = "$-" ] || { error 'fatal: trace_exec: errexit shell option must be off prior to invocation'; exit 3; }
    [ -z "${__te_cmd+x}" ] && [ -z "${__te_log_file+x}" ] && [ -z "${__te_exit_status+x}" ] || exit 3
    [ $# -eq 2 ] || exit 3
    readonly __te_cmd="$1" __te_log_file="$2"

    if [ "${-#*x}" = "$-" ]; then
        # Execution tracing's not on.
        # We'll enable it in a subshell.
        ( set -x && ${__te_cmd} ) >"${__te_log_file}" 2>&1
    else
        # Execution tracing's already on.
        # We'll manually print out the redirected trace after execution.
        ( ${__te_cmd} ) >"${__te_log_file}" 2>&1; __te_exit_status=$?
        cat "${__te_log_file}"
        return ${__te_exit_status}
    fi
)

# Define constants.
readonly rt_log_file='test-results.log'

# Define test harness function.
run_test() (
    [ "${-#*e}" != "$-" ] || { error 'fatal: run_test: errexit shell option must be on prior to invocation'; exit 3; }
    [ -n "${rt_log_file+x}" ] || exit 3
    [ -z "${__rt_name+x}" ] && [ -z "${__rt_setup+x}" ] && [ -z "${__rt_exercise+x}" ] && [ -z "${__rt_verify+x}" ] && [ -z "${__rt_temp_dir+x}" ] && [ -z "${__rt_setup_log_file+x}" ] && [ -z "${__rt_exercise_log_file+x}" ] && [ -z "${__rt_verify_log_file+x}" ] && [ -z "${__rt_setup_exit_status+x}" ] && [ -z "${__rt_exercise_exit_status+x}" ] && [ -z "${__rt_verify_exit_status+x}" ] && [ -z "${__rt_result+x}" ] && [ -z "${__rt_exit_status+x}" ] || exit 3
    [ $# -eq 4 ] || exit 3
    readonly __rt_name="$1" __rt_setup="$2" __rt_exercise="$3" __rt_verify="$4"

    # shellcheck disable=SC2030
    __rt_temp_dir="$(mktemp -d)" || { error 'fatal: run_test: failed to create temp directory'; exit 2; }
    readonly __rt_temp_dir
    __rt_teardown() { rm -rf "${__rt_temp_dir}" || { error 'fatal: run_test: failed to remove temp directory'; exit 2; } }; trap __rt_teardown EXIT

    readonly __rt_setup_log_file="${__rt_temp_dir}/.setup.log" __rt_exercise_log_file="${__rt_temp_dir}/.exercise.log" __rt_verify_log_file="${__rt_temp_dir}/.verify.log"
    touch "${__rt_setup_log_file}" "${__rt_exercise_log_file}" "${__rt_verify_log_file}" || { error 'fatal: run_test: failed to create phase log files'; exit 2; }

    set +e; trace_exec "${__rt_setup}" "${__rt_setup_log_file}"; __rt_setup_exit_status=$?; set -e
    if [ ${__rt_setup_exit_status} -eq 0 ]; then
        set +e; trace_exec "${__rt_exercise}" "${__rt_exercise_log_file}"; __rt_exercise_exit_status=$?; set -e
        if [ ${__rt_exercise_exit_status} -eq 0 ]; then
            set +e; trace_exec "${__rt_verify}" "${__rt_verify_log_file}"; __rt_verify_exit_status=$?; set -e
            if [ ${__rt_verify_exit_status} -eq 0 ]; then
                readonly __rt_result='PASS' __rt_exit_status=0
            else
                readonly __rt_result='FAIL' __rt_exit_status=1
            fi
        else readonly __rt_result='ERROR' __rt_exit_status=1; fi
    else readonly __rt_result='ERROR' __rt_exit_status=1; fi

    __rt_panic_over_untouchable_log_file() { error 'fatal: run_test: failed to append to log file'; exit 2; }
    if [ ${__rt_exit_status} -eq 0 ]; then
        __rt_log_phase() { cat >>"${rt_log_file}" || __rt_panic_over_untouchable_log_file; }
    else
        __rt_log_phase() { tee -a "${rt_log_file}" || __rt_panic_over_untouchable_log_file; }
    fi
    printf '>>>>>>>> test > %-72s [%5s]\n' "${__rt_name}" "${__rt_result}" | tee -a "${rt_log_file}" || __rt_panic_over_untouchable_log_file
    sed 's/^/        setup > /' "${__rt_setup_log_file}" | __rt_log_phase
    sed 's/^/     exercise > /' "${__rt_exercise_log_file}" | __rt_log_phase
    sed 's/^/       verify > /' "${__rt_verify_log_file}" | __rt_log_phase

    return ${__rt_exit_status}
)

# Define raison d'être functions.

init() {
    [ -z "${script_file+x}" ] && [ -z "${res_dir+x}" ] && [ -z "${GIT_EXEC_PATH+x}" ] && [ -z "${sync_subcmd+x}" ] || exit 3
    [ $# -eq 2 ] || { error "usage: $0 <git-sync script> <resources directory>"; return 1; }
    script_file="$(greadlink -e "$1" 2>/dev/null)" || script_file="$(readlink -e "$1" 2>/dev/null)" || { error "fatal: could not canonicalize $1"; return 1; }
    res_dir="$(greadlink -e "$2" 2>/dev/null)" || res_dir="$(readlink -e "$2" 2>/dev/null)" || { error "fatal: could not canonicalize $2"; return 1; }
    readonly script_file res_dir

    [ -f "${script_file}" ] || { error "fatal: ${script_file} is not a file"; return 1; }
    [ -x "${script_file}" ] || { error "fatal: ${script_file} is not executable"; return 1; }
    [ -d "${res_dir}" ] || { error "fatal: ${res_dir} is not a directory"; return 1; }
    GIT_EXEC_PATH="$(dirname "${script_file}")" || exit 2
    export GIT_EXEC_PATH
    readonly sync_subcmd="${script_file##*/git-}"
}

lint() (
    [ -n "${script_file+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    verify() { shellcheck --shell='sh' "${script_file}"; }
    run_test 'static analysis: ShellCheck' '' '' verify
)

test_usage_safeguards_help() (
    [ -n "${sync_subcmd+x}" ] || exit 3
    [ -z "${__tush_invocation_log_file+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    derive_shared_state() {
        # shellcheck disable=SC2031
        readonly __tush_invocation_log_file="${__rt_temp_dir}/invocation.log"
    }
    exercise() {
        derive_shared_state
        git "${sync_subcmd}" 2>&1 | tee "${__tush_invocation_log_file}"
    }
    verify() {
        derive_shared_state
        diff -U 3 - "${__tush_invocation_log_file}" <<EOF
usage: git ${sync_subcmd} <remote name>
EOF
    }
    run_test 'usage safeguards: help' '' exercise verify
)

test_usage_safeguards_nonrepo() (
    [ -n "${sync_subcmd+x}" ] || exit 3
    [ -z "${__tusn_repo_dir+x}" ] && [ -z "${__tusn_invocation_log_file+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    derive_shared_state() {
        # shellcheck disable=SC2031
        readonly __tusn_repo_dir="${__rt_temp_dir}/repo" __tusn_invocation_log_file="${__rt_temp_dir}/invocation.log"
    }
    setup() {
        derive_shared_state
        mkdir "${__tusn_repo_dir}"
    }
    exercise() {
        derive_shared_state
        git -C "${__tusn_repo_dir}" "${sync_subcmd}" does-not-matter 2>&1 | tee "${__tusn_invocation_log_file}"
    }
    verify() {
        derive_shared_state
        diff -U 3 - "${__tusn_invocation_log_file}" <<'EOF'
fatal: Not a git repository (or any of the parent directories): .git
EOF
    }
    run_test 'usage safeguards: non-repo' setup exercise verify
)

test_usage_safeguards_batch_1() (
    [ -n "${sync_subcmd+x}" ] || exit 3
    [ -z "${__tusb1_repo_dir+x}" ] && [ -z "${__tusb1_invocation_log_file+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    derive_shared_state() {
        # shellcheck disable=SC2031
        readonly __tusb1_repo_dir="${__rt_temp_dir}/repo" __tusb1_invocation_log_file="${__rt_temp_dir}/invocation.log"
    }
    setup() {
        derive_shared_state
        git init "${__tusb1_repo_dir}" &&
        touch "${__tusb1_repo_dir}/untracked-file" &&
        touch "${__tusb1_repo_dir}/.git/refs/sync"
    }
    exercise() {
        derive_shared_state
        git -C "${__tusb1_repo_dir}" "${sync_subcmd}" ^invalid 2>&1 | tee "${__tusb1_invocation_log_file}"
    }
    verify() {
        derive_shared_state
        diff -U 3 - "${__tusb1_invocation_log_file}" <<'EOF'
fatal: '^invalid' is not a valid remote name
fatal: working tree is dirty
fatal: refs/sync/ is not empty
EOF
    }
    run_test 'usage safeguards: batch #1' setup exercise verify
)

test_usage_safeguards_batch_2() (
    [ -n "${sync_subcmd+x}" ] || exit 3
    [ -z "${__tusb2_repo_dir+x}" ] && [ -z "${__tusb2_invocation_log_file+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    derive_shared_state() {
        # shellcheck disable=SC2031
        readonly __tusb2_repo_dir="${__rt_temp_dir}/repo" __tusb2_invocation_log_file="${__rt_temp_dir}/invocation.log"
    }
    setup() {
        derive_shared_state
        git init "${__tusb2_repo_dir}" &&
        touch "${__tusb2_repo_dir}/staged-file" &&
        git -C "${__tusb2_repo_dir}" add "${__tusb2_repo_dir}/staged-file" &&
        mkdir "${__tusb2_repo_dir}/.git/refs/sync"
    }
    exercise() {
        derive_shared_state
        git -C "${__tusb2_repo_dir}" "${sync_subcmd}" does-not-exist 2>&1 | tee "${__tusb2_invocation_log_file}"
    }
    verify() {
        derive_shared_state
        diff -U 3 - "${__tusb2_invocation_log_file}" <<'EOF'
fatal: 'does-not-exist' is not a named remote
fatal: working tree is dirty
EOF
    }
    run_test 'usage safeguards: batch #2' setup exercise verify
)

test_usage_safeguards_batch_3() (
    [ -n "${res_dir+x}" ] && [ -n "${sync_subcmd+x}" ] || exit 3
    [ -z "${__tusb3_repo_dir+x}" ] && [ -z "${__tusb3_invocation_log_file+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    derive_shared_state() {
        # shellcheck disable=SC2031
        readonly __tusb3_repo_dir="${__rt_temp_dir}/repo" __tusb3_invocation_log_file="${__rt_temp_dir}/invocation.log"
    }
    setup() {
        derive_shared_state
        git clone "${res_dir}/usage-safeguards/batch-3.bundle" "${__tusb3_repo_dir}" &&
        git -C "${__tusb3_repo_dir}" remote add funky-but-valid/a\"\$\'.b /dev/null &&
        git -C "${__tusb3_repo_dir}" update-ref 'refs/sync/interferer' 'b04eff23e104aca9a0ad5453337c7fa5ded8981d' '' &&
        git -C "${__tusb3_repo_dir}" pack-refs --all &&
        rm -rf "${__tusb3_repo_dir}/.git/refs/sync"
    }
    exercise() {
        derive_shared_state
        git -C "${__tusb3_repo_dir}" "${sync_subcmd}" funky-but-valid/a\"\$\'.b 2>&1 | tee "${__tusb3_invocation_log_file}"
    }
    verify() {
        derive_shared_state
        diff -U 3 - "${__tusb3_invocation_log_file}" <<'EOF'
fatal: refs/sync/ is not empty
EOF
    }
    run_test 'usage safeguards: batch #3' setup exercise verify
)

test_usage_safeguards_batch_4() (
    [ -n "${sync_subcmd+x}" ] || exit 3
    [ -z "${__tusb4_repo_dir+x}" ] && [ -z "${__tusb4_invocation_log_file+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    derive_shared_state() {
        # shellcheck disable=SC2031
        readonly __tusb4_repo_dir="${__rt_temp_dir}/repo" __tusb4_invocation_log_file="${__rt_temp_dir}/invocation.log"
    }
    setup() {
        derive_shared_state
        git init "${__tusb4_repo_dir}" &&
        git -C "${__tusb4_repo_dir}" remote add custom /dev/null &&
        git -C "${__tusb4_repo_dir}" config --add 'remote.custom.fetch' '+refs/notes/*:refs/notes/*' &&
        mkdir -p "${__tusb4_repo_dir}/.git/refs/sync/local/heads/contrived" &&
        touch "${__tusb4_repo_dir}/.git/refs/sync/local/heads/contrived/interferer"
    }
    exercise() {
        derive_shared_state
        git -C "${__tusb4_repo_dir}" "${sync_subcmd}" custom 2>&1 | tee "${__tusb4_invocation_log_file}"
    }
    verify() {
        derive_shared_state
        diff -U 3 - "${__tusb4_invocation_log_file}" <<'EOF'
fatal: 'custom' has a non-default fetch refspec configured
fatal: refs/sync/ is not empty
EOF
    }
    run_test 'usage safeguards: batch #4' setup exercise verify
)

test_usage_safeguards() {
    [ $# -eq 0 ] || exit 3

    eager_and test_usage_safeguards_help test_usage_safeguards_nonrepo test_usage_safeguards_batch_1 test_usage_safeguards_batch_2 test_usage_safeguards_batch_3 test_usage_safeguards_batch_4
}

# Do it.
init "$@" && lint && test_usage_safeguards
