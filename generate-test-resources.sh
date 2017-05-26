#!/bin/sh -eux

# Define trivial helper functions.
error() { echo "$@" >&2; }

# Define Git helper functions.

ensure_reproducibility() {
    [ -z "${GIT_AUTHOR_NAME+x}" ] && [ -z "${GIT_AUTHOR_EMAIL+x}" ] && [ -z "${GIT_AUTHOR_DATE+x}" ] && [ -z "${GIT_COMMITTER_NAME+x}" ] && [ -z "${GIT_COMMITTER_EMAIL+x}" ] && [ -z "${GIT_COMMITTER_DATE+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    # Ensure our generated commit and annotated tag objects are reproducible.
    export GIT_AUTHOR_NAME='J. Random'
    export GIT_AUTHOR_EMAIL='jrandom@example.com'
    export GIT_AUTHOR_DATE='Thu, 7 Apr 2005 15:13:13 -0700'
    export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}" GIT_COMMITTER_DATE="${GIT_AUTHOR_DATE}"
}

create_ephemeral_repo() {
    [ -z "${__cer_repo_dir+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    __cer_repo_dir="$(mktemp -d)" || { error 'fatal: create_ephemeral_repo: failed to create temp directory'; exit 2; }
    readonly __cer_repo_dir
    __cer_teardown() { rm -rf "${__cer_repo_dir}" || { error 'fatal: create_ephemeral_repo: failed to remove temp directory'; exit 2; } }; trap __cer_teardown EXIT

    git init "${__cer_repo_dir}"
}

_git() {
    [ -n "${__cer_repo_dir+x}" ] || exit 3

    git -C "${__cer_repo_dir}" "$@"
}

add_file_and_commit() (
    [ -n "${__cer_repo_dir+x}" ] || exit 3
    [ -z "${__afac_nonce+x}" ] && [ -z "${__afac_file+x}" ] || exit 3
    [ $# -eq 1 ] || exit 3
    readonly __afac_nonce="$1" __afac_file="${__cer_repo_dir}/$1"

    echo "${__afac_nonce}" >"${__afac_file}" &&
    _git add "${__afac_file}" &&
    _git commit -m "Add ${__afac_nonce}"
)

create_bundle() (
    [ -n "${res_dir+x}" ] || exit 3
    [ -z "${__cb_file+x}" ] || exit 3
    [ $# -ge 2 ] || exit 3
    readonly __cb_file="${res_dir}/$1"; shift

    mkdir -p "$(dirname "${__cb_file}")" &&
    _git bundle create "${__cb_file}" "$@"
)

# Define raison d'être functions.

init() {
    [ -z "${res_dir+x}" ] || exit 3
    [ $# -eq 1 ] || { error "usage: $0 <resources directory>"; return 1; }
    res_dir="$(greadlink -f "$1" 2>/dev/null)" || res_dir="$(readlink -f "$1" 2>/dev/null)" || { error "fatal: could not canonicalize $1"; return 1; }
    readonly res_dir

    [ -d "${res_dir}" ] || mkdir "${res_dir}" || { error "fatal: could not create directory ${res_dir}"; return 1; }
    ensure_reproducibility
}

generate_usage_safeguards_batch_3_repo() (
    [ $# -eq 0 ] || exit 3

    create_ephemeral_repo &&
    add_file_and_commit 'foo' &&
    create_bundle 'usage-safeguards/batch-3.bundle' --all
)

# Do it.
init "$@" && generate_usage_safeguards_batch_3_repo
