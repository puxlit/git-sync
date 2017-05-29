#!/bin/sh -eux

# Define immutables.
readonly ASCII_RS="$(printf '\036')"
readonly ASCII_US="$(printf '\037')"
readonly DEFAULT_IFS="${IFS}"

# Define trivial helper functions.

error() { echo "$@" >&2; }

circular_shift_set() (
    [ -z "${__css_arg+x}" ] && [ -z "${__css_i+x}" ] || exit 3

    for __css_arg in "$@"; do
        { [ "${__css_arg#*${ASCII_US}}" = "${__css_arg}" ] && [ "${__css_arg#*${ASCII_RS}}" = "${__css_arg}" ]; } || { error 'fatal: circular_shift_set: an argument contains a reserved delimiter'; exit 3; }
    done

    __css_i=0; while true; do
        ( IFS="${ASCII_US}"; printf '%s' "$*" )
        __css_i=$((__css_i+1)); if [ ${__css_i} -ge $# ]; then break; fi
        printf '%s' "${ASCII_RS}"
        __css_arg="$1"; shift; set "$@" "${__css_arg}"
    done
)

power_set() (
    [ -z "${__ps_arg+x}" ] && [ -z "${__ps_n+x}" ] && [ -z "${__ps_fragment+x}" ] || exit 3

    for __ps_arg in "$@"; do
        { [ "${__ps_arg#*${ASCII_US}}" = "${__ps_arg}" ] && [ "${__ps_arg#*${ASCII_RS}}" = "${__ps_arg}" ]; } || { error 'fatal: power_set: an argument contains a reserved delimiter'; exit 3; }
    done

    # All power sets contain the empty set.
    printf '%s' "${ASCII_RS}"

    # Generate non-empty proper subsets.
    __ps_n=1; __ps_fragment=''
    choose() (
        [ -n "${__ps_n+x}" ] && [ -n "${__ps_fragment+x}" ] || exit 3
        [ $# -ge 1 ] || exit 3

        [ ${__ps_n} -ge 1 ] && [ ${__ps_n} -le $# ] || exit 3

        if [ ${__ps_n} -eq $# ]; then
            ( IFS="${ASCII_US}"; printf '%s' "${__ps_fragment}$*${ASCII_RS}" )
        elif [ ${__ps_n} -eq 1 ]; then
            printf '%s' "${__ps_fragment}$1${ASCII_RS}"

            ( shift; choose "$@" )
        else
            # shellcheck disable=SC2030
            ( __ps_n=$((__ps_n-1)); __ps_fragment="${__ps_fragment}$1${ASCII_US}"; shift; choose "$@" )

            ( shift; choose "$@" )
        fi
    )
    # shellcheck disable=SC2031
    while [ ${__ps_n} -lt $# ]; do choose "$@"; __ps_n=$((__ps_n+1)); done

    # All power sets contain the original set itself.
    ( IFS="${ASCII_US}"; printf '%s' "$*" )
)

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

restart_master() {
    [ $# -eq 0 ] || exit 3

    _git checkout --detach &&
    _git branch -d 'master' &&
    _git checkout --orphan 'master' &&
    _git rm -rf .
}

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

# Generate prototypal repos (used primarily by the reconciliation tests).
#
# Bundle filenames encode the contained DAG of commits and refs.
# `c[chain][ordinal]` describes a commit.
# `p[chain][ordinal]` describes a lightweight tag used to pin `c[chain][ordinal]` such that it remains reachable.
# `br[digit]` describes a test branch.
# `lt[digit]` describes a test lightweight tag.
# `at[digit]` describes a test annotated tag.
#
# The set of prototypal repos, partitioned in (reasonably) optimal generation order, follows.
#
#   - partition: `{br,lt,at}0->c00`
#       - `[p00->c00]`                       (before & after)
#       - `[br0->c00]`                       (before & after)
#       - `[lt0->c00]`                       (before & after)
#       - `[at0->c00]`                       (before & after)
#       - `[br0->c00;p00->c00]`              (before & after)
#       - `[c01->c00;br0->c00;p01->c01]`     (before & after)
#       - `[lt0->c00;p00->c00]`              (before & after)
#       - `[at0->c00;p00->c00]`              (before & after)
#       - `[br0->c00;p00->c00;p10->c10]`     (before only)
#       - `[lt0->c00;p00->c00;p10->c10]`     (before only)
#       - `[at0->c00;p00->c00;p10->c10]`     (before only)
#       - partition: `br1->c*`
#           - `[br0->c00;br1->c10]`          (before only)
#           - `[c01->c00;br0->c00;br1->c01]` (before only)
#   - partition: `{br,lt,at}0->c10`
#       - `[br0->c10]`                       (after only)
#       - `[lt0->c10]`                       (after only)
#       - `[at0->c10]`                       (after only)
#       - `[p00->c00;br0->c10]`              (before & after)
#       - `[p00->c00;lt0->c10]`              (before & after)
#       - `[p00->c00;at0->c10]`              (before & after)
#       - `[p00->c00;br0->c10;p10->c10]`     (after only)
#       - `[p00->c00;lt0->c10;p10->c10]`     (after only)
#       - `[p00->c00;at0->c10;p10->c10]`     (after only)
#   - partition: `br0->c01`
#       - `[c01->c00;br0->c01]`              (before & after)
#       - `[c01->c00;p00->c00;br0->c01]`     (before & after)
#       - `[c01->c00;br0->c01;p01->c01]`     (before & after)
#   - partition: `br0->c11`
#       - `[c11->c00;c11->c10;br0->c11]`     (after only)
#
# Additionally, we create a special "local" bundle (comprising the refs `local_br`, `local_lt`, and `local_at`).
generate_prototypal_repos() (
    [ $# -eq 0 ] || exit 3

    create_prototypal_bundle() (
        [ -z "${__cpb_file_suffix+x}" ] || exit 3
        [ $# -ge 2 ] || exit 3
        readonly __cpb_file_suffix="prototypal-repos/$1.bundle"; shift

        create_bundle "${__cpb_file_suffix}" "$@"
    )

    create_ephemeral_repo &&
    add_file_and_commit 'foo' && _git tag 'p00' &&
    add_file_and_commit 'bar' && _git tag 'p01' &&
    restart_master &&
    add_file_and_commit 'baz' && _git tag 'p10' &&
    _git merge --allow-unrelated-histories -m 'Merge c00 with c10' 'p00' && _git tag 'p11' &&
    restart_master &&
    add_file_and_commit 'qux' && _git branch 'local_br' &&
    restart_master &&
    add_file_and_commit 'quux' && _git tag 'local_lt' &&
    restart_master &&
    add_file_and_commit 'quuux' && _git tag -a -m 'local_at' 'local_at' &&
    _git branch 'br0' 'p00' && _git tag 'lt0' 'p00' && _git tag -a -m 'at0' 'at0' 'p00' &&
    create_prototypal_bundle '[p00->c00]' 'refs/tags/p00' &&
    create_prototypal_bundle '[br0->c00]' 'refs/heads/br0' &&
    create_prototypal_bundle '[lt0->c00]' 'refs/tags/lt0' &&
    create_prototypal_bundle '[at0->c00]' 'refs/tags/at0' &&
    create_prototypal_bundle '[br0->c00;p00->c00]' 'refs/heads/br0' 'refs/tags/p00' &&
    create_prototypal_bundle '[c01->c00;br0->c00;p01->c01]' 'refs/heads/br0' 'refs/tags/p01' &&
    create_prototypal_bundle '[lt0->c00;p00->c00]' 'refs/tags/lt0' 'refs/tags/p00' &&
    create_prototypal_bundle '[at0->c00;p00->c00]' 'refs/tags/at0' 'refs/tags/p00' &&
    create_prototypal_bundle '[br0->c00;p00->c00;p10->c10]' 'refs/heads/br0' 'refs/tags/p00' 'refs/tags/p10' &&
    create_prototypal_bundle '[lt0->c00;p00->c00;p10->c10]' 'refs/tags/lt0' 'refs/tags/p00' 'refs/tags/p10' &&
    create_prototypal_bundle '[at0->c00;p00->c00;p10->c10]' 'refs/tags/at0' 'refs/tags/p00' 'refs/tags/p10' &&
    _git branch 'br1' 'p10' && create_prototypal_bundle '[br0->c00;br1->c10]' 'refs/heads/br0' 'refs/heads/br1' && _git branch -D 'br1' &&
    _git branch 'br1' 'p01' && create_prototypal_bundle '[c01->c00;br0->c00;br1->c01]' 'refs/heads/br0' 'refs/heads/br1' && _git branch -D 'br1' &&
    _git branch -D 'br0' && _git tag -d 'lt0' && _git tag -d 'at0' &&
    _git branch 'br0' 'p10' && _git tag 'lt0' 'p10' && _git tag -a -m 'at0' 'at0' 'p10' &&
    create_prototypal_bundle '[br0->c10]' 'refs/heads/br0' &&
    create_prototypal_bundle '[lt0->c10]' 'refs/tags/lt0' &&
    create_prototypal_bundle '[at0->c10]' 'refs/tags/at0' &&
    create_prototypal_bundle '[p00->c00;br0->c10]' 'refs/tags/p00' 'refs/heads/br0' &&
    create_prototypal_bundle '[p00->c00;lt0->c10]' 'refs/tags/p00' 'refs/tags/lt0' &&
    create_prototypal_bundle '[p00->c00;at0->c10]' 'refs/tags/p00' 'refs/tags/at0' &&
    create_prototypal_bundle '[p00->c00;br0->c10;p10->c10]' 'refs/tags/p00' 'refs/heads/br0' 'refs/tags/p10' &&
    create_prototypal_bundle '[p00->c00;lt0->c10;p10->c10]' 'refs/tags/p00' 'refs/tags/lt0' 'refs/tags/p10' &&
    create_prototypal_bundle '[p00->c00;at0->c10;p10->c10]' 'refs/tags/p00' 'refs/tags/at0' 'refs/tags/p10' &&
    _git branch -D 'br0' && _git tag -d 'lt0' && _git tag -d 'at0' &&
    _git branch 'br0' 'p01' &&
    create_prototypal_bundle '[c01->c00;br0->c01]' 'refs/heads/br0' &&
    create_prototypal_bundle '[c01->c00;p00->c00;br0->c01]' 'refs/tags/p00' 'refs/heads/br0' &&
    create_prototypal_bundle '[c01->c00;br0->c01;p01->c01]' 'refs/heads/br0' 'refs/tags/p01' &&
    _git branch -D 'br0' &&
    _git branch 'br0' 'p11' && create_prototypal_bundle '[c11->c00;c11->c10;br0->c11]' 'refs/heads/br0' && _git branch -D 'br0' &&
    create_prototypal_bundle 'local' 'refs/heads/local_br' 'refs/tags/local_lt' 'refs/tags/local_at'
)

# A (somewhat exhaustive) set of reconciliation scenarios follows.
#
# **Same commits, same refs**
#
# | Δ obs | Δ refs  | Before repo | After repo | Scenario name              |
# | ----- | ------- | ----------- | ---------- | -------------------------- |
# | ` =`  | ` =` br | `br0->c00`  | `br0->c00` | up-to-date branch          |
# | ` =`  | ` =` lt | `lt0->c00`  | `lt0->c00` | up-to-date lightweight tag |
# | ` =`  | ` =` at | `at0->c00`  | `at0->c00` | up-to-date annotated tag   |
#
# **Same commits, new refs** (complements same commits, pruned refs)
#
# | Δ obs | Δ refs  | Before repo | After repo          | Scenario name                          |
# | ----- | ------- | ----------- | ------------------- | -------------------------------------- |
# | ` =`  | ` *` br | `p00->c00`  | `br0->c00;p00->c00` | new branch to existing commit          |
# | ` =`  | ` *` lt | `p00->c00`  | `lt0->c00;p00->c00` | new lightweight tag to existing commit |
# | ` *`  | ` *` at | `p00->c00`  | `at0->c00;p00->c00` | new annotated tag to existing commit   |
#
# **Same commits, updated refs**
#
# | Δ obs | Δ refs  | Before repo                  | After repo                   | Scenario name                                              |
# | ----- | ------- | ---------------------------- | ---------------------------- | ---------------------------------------------------------- |
# | ` =`  | ` >` br | `c01->c00;br0->c00;p01->c01` | `c01->c00;br0->c01;p01->c01` | fast-forward branch to existing commit                     |
# | ` =`  | ` <` br | `c01->c00;br0->c01;p01->c01` | `c01->c00;br0->c00;p01->c01` | rewind branch, no commits lost                             |
# | ` =`  | ` +` br | `br0->c00;p00->c00;p10->c10` | `p00->c00;br0->c10;p10->c10` | force branch update to existing commit, no commits lost    |
# | ` =`  | ` t` lt | `lt0->c00;p00->c00;p10->c10` | `p00->c00;lt0->c10;p10->c10` | lightweight tag update to existing commit, no commits lost |
# | `*-`  | ` t` at | `at0->c00;p00->c00;p10->c10` | `p00->c00;at0->c10;p10->c10` | annotated tag update to existing commit, no commits lost   |
#
# **Same commits, updated and pruned refs**
#
# | Δ obs | Δ refs  | Before repo                  | After repo          | Scenario name                          |
# | ----- | ------- | ---------------------------- | ------------------- | -------------------------------------- |
# | ` =`  | `>-` br | `c01->c00;br0->c00;br1->c01` | `c01->c00;br0->c01` | fast-forward merge, prune topic branch |
#
# **Same commits, pruned refs** (complements same commits, new refs)
#
# | Δ obs | Δ refs  | Before repo         | After repo | Scenario name                          |
# | ----- | ------- | ------------------- | ---------- | -------------------------------------- |
# | ` =`  | ` -` br | `br0->c00;p00->c00` | `p00->c00` | prune branch, no commits lost          |
# | ` =`  | ` -` lt | `lt0->c00;p00->c00` | `p00->c00` | prune lightweight tag, no commits lost |
# | ` -`  | ` -` at | `at0->c00;p00->c00` | `p00->c00` | prune annotated tag, no commits lost   |
#
# **New commits, new refs** (complements pruned commits, pruned refs)
#
# | Δ obs | Δ refs  | Before repo | After repo                   | Scenario name                     |
# | ----- | ------- | ----------- | ---------------------------- | --------------------------------- |
# | ` *`  | ` *` br | `p00->c00`  | `c01->c00;p00->c00;br0->c01` | new branch to new commit          |
# | ` *`  | ` *` br | `p00->c00`  | `p00->c00;br0->c10`          | new orphan branch to new commit   |
# | ` *`  | ` *` lt | `p00->c00`  | `p00->c00;lt0->c10`          | new lightweight tag to new commit |
# | ` *`  | ` *` at | `p00->c00`  | `p00->c00;at0->c10`          | new annotated tag to new commit   |
#
# **New commits, updated refs** (complements pruned commits, updated refs)
#
# | Δ obs | Δ refs  | Before repo         | After repo          | Scenario name                                         |
# | ----- | ------- | ------------------- | ------------------- | ----------------------------------------------------- |
# | ` *`  | ` >` br | `br0->c00`          | `c01->c00;br0->c01` | fast-forward branch to new commit                     |
# | ` *`  | ` +` br | `br0->c00;p00->c00` | `p00->c00;br0->c10` | force branch update to new commit, no commits lost    |
# | ` *`  | ` t` lt | `lt0->c00;p00->c00` | `p00->c00;lt0->c10` | lightweight tag update to new commit, no commits lost |
# | `*-`  | ` t` at | `at0->c00;p00->c00` | `p00->c00;at0->c10` | annotated tag update to new commit, no commits lost   |
#
# **New commits, updated and pruned refs**
#
# | Δ obs | Δ refs  | Before repo         | After repo                   | Scenario name                              |
# | ----- | ------- | ------------------- | ---------------------------- | ------------------------------------------ |
# | ` *`  | `>-` br | `br0->c00;br1->c10` | `c11->c00;c11->c10;br0->c11` | non-fast-forward merge, prune topic branch |
#
# **New and pruned commits, updated refs**
#
# | Δ obs | Δ refs  | Before repo | After repo | Scenario name                                      |
# | ----- | ------- | ----------- | ---------- | -------------------------------------------------- |
# | `*-`  | ` +` br | `br0->c00`  | `br0->c10` | force branch update to new commit, commits lost    |
# | `*-`  | ` t` lt | `lt0->c00`  | `lt0->c10` | lightweight tag update to new commit, commits lost |
# | `*-`  | ` t` at | `at0->c00`  | `at0->c10` | annotated tag update to new commit, commits lost   |
#
# **Pruned commits, updated refs** (complements new commits, updated refs)
#
# | Δ obs | Δ refs  | Before repo         | After repo          | Scenario name                                           |
# | ----- | ------- | ------------------- | ------------------- | ------------------------------------------------------- |
# | ` -`  | ` <` br | `c01->c00;br0->c01` | `br0->c00`          | rewind branch, commits lost                             |
# | ` -`  | ` +` br | `p00->c00;br0->c10` | `br0->c00;p00->c00` | force branch update to existing commit, commits lost    |
# | ` -`  | ` t` lt | `p00->c00;lt0->c10` | `lt0->c00;p00->c00` | lightweight tag update to existing commit, commits lost |
# | `*-`  | ` t` at | `p00->c00;at0->c10` | `at0->c00;p00->c00` | annotated tag update to existing commit, commits lost   |
#
# **Pruned commits, pruned refs** (complements new commits, new refs)
#
# | Δ obs | Δ refs  | Before repo                  | After repo | Scenario name                       |
# | ----- | ------- | ---------------------------- | ---------- | ----------------------------------- |
# | ` -`  | ` -` br | `c01->c00;p00->c00;br0->c01` | `p00->c00` | prune branch, commits lost          |
# | ` -`  | ` -` br | `p00->c00;br0->c10`          | `p00->c00` | prune orphan branch, commits lost   |
# | ` -`  | ` -` lt | `p00->c00;lt0->c10`          | `p00->c00` | prune lightweight tag, commits lost |
# | ` -`  | ` -` at | `p00->c00;at0->c10`          | `p00->c00` | prune annotated tag, commits lost   |
#
# For each scenario, we generate a set of sub-scenarios.
#
# TODO: Add (sub-)scenarios in which new remote refs conflict with existing protected local refs.
generate_reconciliation_scenarios() (
    [ -n "${res_dir+x}" ] || exit 3
    [ -z "${__grs_dir+x}" ] && [ -z "${__grs_manifest_file+x}" ] && [ -z "${__grs_id+x}" ] && [ -z "${__grs_local_refs+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    readonly __grs_dir="${res_dir}/reconciliation-scenarios"
    mkdir "${__grs_dir}" || { error 'fatal: generate_reconciliation_scenarios: failed to create directory'; exit 2; }
    readonly __grs_manifest_file="${__grs_dir}/manifest.txt"
    touch "${__grs_manifest_file}" || { error 'fatal: generate_reconciliation_scenarios: failed to create manifest file'; exit 2; }

    __grs_id=0
    __grs_local_refs="$(git bundle list-heads "${res_dir}/prototypal-repos/local.bundle" | sort -k 2)"
    generate_subscenarios() {
        [ -n "${__grs_id+x}" ] && [ -n "${res_dir+x}" ] && [ -n "${__grs_dir+x}" ] && [ -n "${__grs_local_refs+x}" ] && [ -n "${__grs_manifest_file+x}" ] || exit 3
        [ -z "${__gs_name+x}" ] && [ -z "${__gs_before_bundle_file+x}" ] && [ -z "${__gs_after_bundle_file+x}" ] && [ -z "${__gs_before_refs+x}" ] && [ -z "${__gs_after_refs+x}" ] && [ -z "${__gs_before_branches+x}" ] && [ -z "${__gs_expected_refs+x}" ] && [ -z "${__gs_branch+x}" ] && [ -z "${__gs_scenario_dir+x}" ] && [ -z "${__gs_num_y+x}" ] && [ -z "${__gs_branches_to_checkout+x}" ] && [ -z "${__gs_branches_to_checkout_file+x}" ] && [ -z "${__gs_branch_to_checkout+x}" ] && [ -z "${__gs_num_x+x}" ] && [ -z "${__gs_refs_to_protect+x}" ] && [ -z "${__gs_refs_to_protect_file+x}" ] && [ -z "${__gs_expected_refs_file+x}" ] && [ -z "${__gs_ref_to_protect+x}" ] && [ -z "${__gs_ref+x}" ] && [ -z "${__gs_num_xy+x}" ] && [ -z "${__gs_x+x}" ] && [ -z "${__gs_y+x}" ] && [ -z "${__gs_id+x}" ] && [ -z "${__gs_subscenario_dir+x}" ] || exit 3
        [ $# -eq 3 ] || exit 3

        [ ${__grs_id} -le 99 ] || { error 'fatal: generate_subscenarios: too many scenarios'; exit 3; }

        (
            readonly __gs_name="$1" __gs_before_bundle_file="${res_dir}/prototypal-repos/[$2].bundle" __gs_after_bundle_file="${res_dir}/prototypal-repos/[$3].bundle"
            [ -f "${__gs_before_bundle_file}" ] || { error 'fatal: generate_subscenarios: before bundle file not found'; exit 3; }
            [ -f "${__gs_after_bundle_file}" ] || { error 'fatal: generate_subscenarios: after bundle file not found'; exit 3; }

            __gs_before_refs="$(git bundle list-heads "${__gs_before_bundle_file}" | sort -k 2)"
            __gs_after_refs="$(git bundle list-heads "${__gs_after_bundle_file}" | sort -k 2)"
            __gs_before_branches="$(echo "${__gs_before_refs}" | grep ' refs/heads/br' | sed 's|^.*refs/heads/||')"
            __gs_expected_refs="$({
                echo "${__grs_local_refs}"
                echo "${__gs_after_refs}" | grep ' refs/heads/br' | sed 's| refs/heads/br| refs/remotes/origin/br|'
                for __gs_branch in ${__gs_before_branches}; do echo "${__gs_after_refs}" | grep " refs/heads/${__gs_branch}$" || true; done
                echo "${__gs_after_refs}" | grep ' refs/tags/' || true
            } | sort -k 2)"
            readonly __gs_before_refs __gs_after_refs __gs_before_branches __gs_expected_refs

            readonly __gs_scenario_dir="${__grs_dir}/$(printf '%02d' ${__grs_id})"
            mkdir "${__gs_scenario_dir}" || { error 'fatal: generate_subscenarios: failed to create scenario directory'; exit 2; }

            __gs_num_y=0; IFS="${ASCII_RS}"
            # shellcheck disable=SC2086
            for __gs_branches_to_checkout in $(IFS="${DEFAULT_IFS}"; circular_shift_set 'local_br' ${__gs_before_branches}); do
                __gs_branches_to_checkout_file="${__gs_scenario_dir}/branches_to_checkout.$(printf '%02d' ${__gs_num_y}).txt"
                touch "${__gs_branches_to_checkout_file}" || { error 'fatal: generate_subscenarios: failed to create branches-to-checkout file'; exit 2; }
                ( IFS="${ASCII_US}"; for __gs_branch_to_checkout in ${__gs_branches_to_checkout}; do
                    echo "${__gs_branch_to_checkout}" >>"${__gs_branches_to_checkout_file}"
                done )
                __gs_num_y=$((__gs_num_y+1))
                [ ${__gs_num_y} -le 99 ] || { error 'fatal: generate_subscenarios: too many sub-scenarios'; exit 3; }
            done; IFS="${DEFAULT_IFS}"; readonly __gs_num_y

            __gs_num_x=0; IFS="${ASCII_RS}"
            # shellcheck disable=SC2046
            for __gs_refs_to_protect in $(IFS="${DEFAULT_IFS}"; power_set $(echo "${__gs_before_refs}" | grep -e ' refs/heads/br' -e ' refs/tags/lt' -e ' refs/tags/at' | sed 's|^.*refs/||;s|^heads/|branch.|;s|^tags/|tag.|')); do
                __gs_refs_to_protect_file="${__gs_scenario_dir}/refs_to_protect.$(printf '%02d' ${__gs_num_x}).txt"
                printf 'branch.local_br\ntag.local_lt\ntag.local_at\n' >"${__gs_refs_to_protect_file}" || { error 'fatal: generate_subscenarios: failed to create refs-to-protect file'; exit 2; }
                __gs_expected_refs_file="${__gs_scenario_dir}/expected_refs.$(printf '%02d' ${__gs_num_x}).txt"
                echo "${__gs_expected_refs}" >"${__gs_expected_refs_file}" || { error 'fatal: generate_subscenarios: failed to create expected-refs file'; exit 2; }
                ( IFS="${ASCII_US}"; for __gs_ref_to_protect in ${__gs_refs_to_protect}; do
                    echo "${__gs_ref_to_protect}" >>"${__gs_refs_to_protect_file}"
                    if [ "${__gs_ref_to_protect#branch.}" != "${__gs_ref_to_protect}" ]; then
                        __gs_ref=" refs/heads/${__gs_ref_to_protect#branch.}"
                    elif [ "${__gs_ref_to_protect#tag.}" != "${__gs_ref_to_protect}" ]; then
                        __gs_ref=" refs/tags/${__gs_ref_to_protect#tag.}"
                    fi
                    ed -s "${__gs_expected_refs_file}" <<EOF
g/$(echo "${__gs_ref}" | sed 's|/|\\/|g')/d
w
EOF
                    echo "${__gs_before_refs}" | grep "${__gs_ref}$" >>"${__gs_expected_refs_file}"
                done )
                sort -o "${__gs_expected_refs_file}" -k 2 "${__gs_expected_refs_file}"
                __gs_num_x=$((__gs_num_x+1))
                [ ${__gs_num_x} -le 99 ] || { error 'fatal: generate_subscenarios: too many sub-scenarios'; exit 3; }
            done; IFS="${DEFAULT_IFS}"; readonly __gs_num_x

            __gs_num_xy=$((__gs_num_x*__gs_num_y))
            __gs_x=0; while [ ${__gs_x} -lt ${__gs_num_x} ]; do
                __gs_refs_to_protect_file="${__gs_scenario_dir}/refs_to_protect.$(printf '%02d' ${__gs_x}).txt"
                __gs_expected_refs_file="${__gs_scenario_dir}/expected_refs.$(printf '%02d' ${__gs_x}).txt"

                __gs_y=0; while [ ${__gs_y} -lt ${__gs_num_y} ]; do
                __gs_branches_to_checkout_file="${__gs_scenario_dir}/branches_to_checkout.$(printf '%02d' ${__gs_y}).txt"

                    __gs_id="$(printf '%02d-%02d-%02d' ${__grs_id} ${__gs_x} ${__gs_y})"
                    __gs_subscenario_dir="${__grs_dir}/${__gs_id}"
                    mkdir "${__gs_subscenario_dir}" || { error 'fatal: generate_subscenarios: failed to create sub-scenario directory'; exit 2; }

                    ln -s "${__gs_before_bundle_file}" "${__gs_subscenario_dir}/before.bundle"
                    ln -s "${__gs_after_bundle_file}" "${__gs_subscenario_dir}/after.bundle"
                    ln -s "${__gs_branches_to_checkout_file}" "${__gs_subscenario_dir}/branches_to_checkout.txt"
                    ln -s "${__gs_refs_to_protect_file}" "${__gs_subscenario_dir}/refs_to_protect.txt"
                    ln -s "${__gs_expected_refs_file}" "${__gs_subscenario_dir}/expected_refs.txt"

                    printf '%s: %s (%d of %d)\n' "${__gs_id}" "${__gs_name}" $(((__gs_x*__gs_num_y)+__gs_y+1)) ${__gs_num_xy} >>"${__grs_manifest_file}"
                __gs_y=$((__gs_y+1)); done
            __gs_x=$((__gs_x+1)); done
        )

        __grs_id=$((__grs_id+1))
    }

    generate_subscenarios 'up-to-date branch' 'br0->c00' 'br0->c00' &&
    generate_subscenarios 'up-to-date lightweight tag' 'lt0->c00' 'lt0->c00' &&
    generate_subscenarios 'up-to-date annotated tag' 'at0->c00' 'at0->c00' &&
    generate_subscenarios 'new branch to existing commit' 'p00->c00' 'br0->c00;p00->c00' &&
    generate_subscenarios 'new lightweight tag to existing commit' 'p00->c00' 'lt0->c00;p00->c00' &&
    generate_subscenarios 'new annotated tag to existing commit' 'p00->c00' 'at0->c00;p00->c00' &&
    generate_subscenarios 'fast-forward branch to existing commit' 'c01->c00;br0->c00;p01->c01' 'c01->c00;br0->c01;p01->c01' &&
    generate_subscenarios 'rewind branch, no commits lost' 'c01->c00;br0->c01;p01->c01' 'c01->c00;br0->c00;p01->c01' &&
    generate_subscenarios 'force branch update to existing commit, no commits lost' 'br0->c00;p00->c00;p10->c10' 'p00->c00;br0->c10;p10->c10' &&
    generate_subscenarios 'lightweight tag update to existing commit, no commits lost' 'lt0->c00;p00->c00;p10->c10' 'p00->c00;lt0->c10;p10->c10' &&
    generate_subscenarios 'annotated tag update to existing commit, no commits lost' 'at0->c00;p00->c00;p10->c10' 'p00->c00;at0->c10;p10->c10' &&
    generate_subscenarios 'fast-forward merge, prune topic branch' 'c01->c00;br0->c00;br1->c01' 'c01->c00;br0->c01' &&
    generate_subscenarios 'prune branch, no commits lost' 'br0->c00;p00->c00' 'p00->c00' &&
    generate_subscenarios 'prune lightweight tag, no commits lost' 'lt0->c00;p00->c00' 'p00->c00' &&
    generate_subscenarios 'prune annotated tag, no commits lost' 'at0->c00;p00->c00' 'p00->c00' &&
    generate_subscenarios 'new branch to new commit' 'p00->c00' 'c01->c00;p00->c00;br0->c01' &&
    generate_subscenarios 'new orphan branch to new commit' 'p00->c00' 'p00->c00;br0->c10' &&
    generate_subscenarios 'new lightweight tag to new commit' 'p00->c00' 'p00->c00;lt0->c10' &&
    generate_subscenarios 'new annotated tag to new commit' 'p00->c00' 'p00->c00;at0->c10' &&
    generate_subscenarios 'fast-forward branch to new commit' 'br0->c00' 'c01->c00;br0->c01' &&
    generate_subscenarios 'force branch update to new commit, no commits lost' 'br0->c00;p00->c00' 'p00->c00;br0->c10' &&
    generate_subscenarios 'lightweight tag update to new commit, no commits lost' 'lt0->c00;p00->c00' 'p00->c00;lt0->c10' &&
    generate_subscenarios 'annotated tag update to new commit, no commits lost' 'at0->c00;p00->c00' 'p00->c00;at0->c10' &&
    generate_subscenarios 'non-fast-forward merge, prune topic branch' 'br0->c00;br1->c10' 'c11->c00;c11->c10;br0->c11' &&
    generate_subscenarios 'force branch update to new commit, commits lost' 'br0->c00' 'br0->c10' &&
    generate_subscenarios 'lightweight tag update to new commit, commits lost' 'lt0->c00' 'lt0->c10' &&
    generate_subscenarios 'annotated tag update to new commit, commits lost' 'at0->c00' 'at0->c10' &&
    generate_subscenarios 'rewind branch, commits lost' 'c01->c00;br0->c01' 'br0->c00' &&
    generate_subscenarios 'force branch update to existing commit, commits lost' 'p00->c00;br0->c10' 'br0->c00;p00->c00' &&
    generate_subscenarios 'lightweight tag update to existing commit, commits lost' 'p00->c00;lt0->c10' 'lt0->c00;p00->c00' &&
    generate_subscenarios 'annotated tag update to existing commit, commits lost' 'p00->c00;at0->c10' 'at0->c00;p00->c00' &&
    generate_subscenarios 'prune branch, commits lost' 'c01->c00;p00->c00;br0->c01' 'p00->c00' &&
    generate_subscenarios 'prune orphan branch, commits lost' 'p00->c00;br0->c10' 'p00->c00' &&
    generate_subscenarios 'prune lightweight tag, commits lost' 'p00->c00;lt0->c10' 'p00->c00' &&
    generate_subscenarios 'prune annotated tag, commits lost' 'p00->c00;at0->c10' 'p00->c00'
)

# Do it.
init "$@" && generate_prototypal_repos && generate_reconciliation_scenarios
