#!/bin/sh -eux

# Define trivial helper functions.
error() { echo "$@" >&2; }

# Define Git helper function.
ensure_reproducibility() {
    [ -z "${GIT_AUTHOR_NAME+x}" ] && [ -z "${GIT_AUTHOR_EMAIL+x}" ] && [ -z "${GIT_AUTHOR_DATE+x}" ] && [ -z "${GIT_COMMITTER_NAME+x}" ] && [ -z "${GIT_COMMITTER_EMAIL+x}" ] && [ -z "${GIT_COMMITTER_DATE+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    # Ensure our generated commit and annotated tag objects are reproducible.
    export GIT_AUTHOR_NAME='J. Random'
    export GIT_AUTHOR_EMAIL='j@random.example'
    export GIT_AUTHOR_DATE='Thu, 7 Apr 2005 15:13:13 -0700'
    export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}" GIT_COMMITTER_DATE="${GIT_AUTHOR_DATE}"
}

# Define raison d'être functions.

init() {
    [ -z "${res_dir+x}" ] || exit 3
    [ $# -eq 1 ] || { error "usage: $0 <resources directory>"; return 1; }
    res_dir="$(greadlink -f "$1" 2>/dev/null)" || res_dir="$(readlink -f "$1" 2>/dev/null)" || { error "fatal: could not canonicalize $1"; return 1; }
    readonly res_dir

    [ -d "${res_dir}" ] || mkdir "${res_dir}" || { error "fatal: could not create directory ${res_dir}"; return 1; }
    ensure_reproducibility
}

generate_simple_repo() (
    [ -n "${res_dir+x}" ] || exit 3
    [ -z "${__gsr_repo_dir+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    __gsr_repo_dir="$(mktemp -d)" || { error 'fatal: generate_simple_repo: failed to create temp directory'; exit 2; }
    readonly __gsr_repo_dir
    __gsr_teardown() { rm -rf "${__gsr_repo_dir}" || { error 'fatal: generate_simple_repo: failed to remove temp directory'; exit 2; } }; trap __gsr_teardown EXIT

    git init "${__gsr_repo_dir}" &&
    echo 'foo' >"${__gsr_repo_dir}/foo" &&
    git -C "${__gsr_repo_dir}" add "${__gsr_repo_dir}/foo" &&
    git -C "${__gsr_repo_dir}" commit -m 'Initial commit' &&
    git -C "${__gsr_repo_dir}" bundle create "${res_dir}/simple.bundle" --all
)

# Do it.
init "$@" && generate_simple_repo
