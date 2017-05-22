#!/bin/sh -eux

# Define trivial helper functions.
error() { echo "$@" >&2; }
yesno() (
    [ -z "${__yn_prompt+x}" ] && [ -z "${__yn_response+x}" ] || exit 3
    [ $# -eq 1 ] || exit 3
    readonly __yn_prompt="$1"

    while true; do
        # We're using `printf` to elide the newline in a POSIX-compliant manner.
        printf '%s' "${__yn_prompt}"
        read -r __yn_response
        [ "${__yn_response}" = 'y' ] && return 0
        [ "${__yn_response}" = 'n' ] && return 1
    done
)

# Define constants.
readonly sync_refs_namespace='refs/sync/'

# Divvy up the meat and potatoes of `git-sync` into the following functions.

parse_args() {
    [ -z "${remote_name+x}" ] || exit 3
    [ $# -eq 1 ] || { error "usage: git ${0##*/git-} <remote name>"; return 1; }
    readonly remote_name="$1"
}

check_sanity() {
    [ -n "${sync_refs_namespace+x}" ] && [ -n "${remote_name+x}" ] || exit 3
    [ -z "${sync_refs_dir+x}" ] && [ -z "${__cs_exit_status+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    # Implicit/unchecked preconditions: (i) file system is stable; and (ii) nothing else is messing with the repository for the duration of our execution.
    #
    # TODO: Determine the minimum version of Git required, and assert we have that on hand.

    # Kill two birds with one stone:
    #
    #   - ensure Git can locate the repository; and
    #   - resolve the path to our sync refs namespace (for later use).
    #
    # `git-rev-parse` will print a nice error for us if it can't locate the repository, so all we need to do is bail.
    #
    # We're stripping the trailing forward slash from `${sync_refs_namespace}` so the resultant path won't end with a trailing forward slash.
    # The separate `readonly` and `|| return 1` construct exist to sate the peculiarities of `set -e`; see <http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_22_16> and <http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_25_16> respectively for details.
    sync_refs_dir="$(git rev-parse --git-path "${sync_refs_namespace%%/}")" || return 1
    readonly sync_refs_dir

    (
        # Accumulate errors (where practical) for the remaining sanity checks, so the user can fix 'em up in one go.
        __cs_exit_status=0

        # Ensure we have a valid named remote.
        if git check-ref-format "refs/remotes/${remote_name}"; then
            if git config --get "remote.${remote_name}.url" >/dev/null; then
                # Ensure that remote is configured with a stock standard fetch refspec.
                [ "$(git config --get-all "remote.${remote_name}.fetch" | grep -Fcvx "+refs/heads/*:refs/remotes/${remote_name}/*")" -eq 0 ] || { error "fatal: '${remote_name}' has a non-default fetch refspec configured"; __cs_exit_status=1; }
            else error "fatal: '${remote_name}' is not a named remote"; __cs_exit_status=1; fi
        else error "fatal: '${remote_name}' is not a valid remote name"; __cs_exit_status=1; fi

        # Ensure our working tree is clean.
        [ "$(git status --porcelain | wc -l)" -eq 0 ] || { error 'fatal: working tree is dirty'; __cs_exit_status=1; }

        # TODO: Ensure there's no rebase in progress.

        # Ensure our sync refs namespace is empty.
        # Ideally, this means the last component of the path to our sync refs namespace (which we resolved earlier) doesn't exist.
        # If it _does_ exist, it had better be a directory, and there had better be no refs inside.
        # (We can test that last part by seeing if we can enumerate at least one ref inside our sync refs namespace.)
        [ ! -e "${sync_refs_dir}" ] ||
        ( [ -d "${sync_refs_dir}" ] && [ "$(git for-each-ref --count=1 "${sync_refs_namespace}" | wc -l)" -eq 0 ] ) ||
        { error "fatal: ${sync_refs_namespace} is not empty"; __cs_exit_status=1; }

        return ${__cs_exit_status}
    )
}

prime_clean_up() {
    [ -n "${sync_refs_dir+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    clean_up() {
        # Obliterate our sync refs namespace.
        # We _could_ do this with plumbing commands, which would free us from implementation details.
        #
        # ```
        # git for-each-ref --format='delete %(refname)' "${sync_refs_namespace}" | git update-ref --stdin
        # ```
        #
        # However, it's easier to just nuke the directory, since we know where it resides.
        rm -rf "${sync_refs_dir}"
    }

    # Clean up after ourselves when we eventually terminate.
    trap clean_up EXIT
}

preserve_local_refs() {
    [ -n "${sync_refs_namespace+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    # Enumerate all branches and tags configured for immunity from `git-sync`, massage them into refspecs that populate our local sync refs namespace, then do the deed with `git-fetch`.
    #
    # Note that per the docs, the keys that are matched against and printed are canonicalised such that section and variable names are lowercased.
    git config --bool --name-only --get-regexp '^(branch|tag)\.(.+)\.protectfromsync$' 'true' | sed -e 's|\.protectfromsync$||' -e 's|^branch\.|heads/|' -e 's|^tag\.|tags/|' -e "s|^.*$|refs/&:${sync_refs_namespace}local/&|" | xargs git fetch --quiet .
}

fetch_from_remote() {
    [ -n "${remote_name+x}" ] && [ -n "${sync_refs_namespace+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    # We don't want `git-fetch` to update as per the default configuration variable `remote.${remote_name}.fetch` (hence `--refmap=''`) or our local tags (hence `--no-tags`).
    # We expect our remote sync refs namespace to be empty, so we shouldn't have any refs to delete (hence no `--prune`) or force update (hence no plus `+` prefixes for our refspecs).
    git fetch --quiet --refmap='' --no-tags "${remote_name}" "refs/heads/*:${sync_refs_namespace}remote/heads/*" "refs/tags/*:${sync_refs_namespace}remote/tags/*"
}

reconcile() {
    [ -n "${sync_refs_namespace+x}" ] && [ -n "${remote_name+x}" ] || exit 3
    [ $# -eq 0 ] || exit 3

    # Summarise updates to local branches and tags, then prompt for whether we should proceed.
    #
    # TODO: Only prompt if destructive updates are implicated.
    git fetch --dry-run --update-head-ok --prune . "${sync_refs_namespace}local/heads/*:refs/heads/*" "${sync_refs_namespace}local/tags/*:refs/tags/*" "+${sync_refs_namespace}remote/heads/*:refs/heads/*" "+${sync_refs_namespace}remote/tags/*:refs/tags/*"
    yesno 'Continue [y,n]? ' || return 1

    # Update remote-tracking branches, then update local branches and tags.
    #
    # Eagle-eyed readers will notice our local update fetch differs from the dry-run, in that it is passed the `--no-tags` option.
    # Without it, we wind up re-creating tags that we just deleted.
    #
    # TODO: Instead of fetching with `--update-head-ok` then resetting the index and working tree, consider saving our current branch (if applicable, with `git symbolic-ref --short HEAD`), detaching HEAD (with `git checkout --detach`), performing our updates, then checking out our saved current branch (if applicable).
    git fetch --update-head-ok --prune . "+${sync_refs_namespace}remote/heads/*:refs/remotes/${remote_name}/*"
    git fetch --update-head-ok --prune --no-tags . "${sync_refs_namespace}local/heads/*:refs/heads/*" "${sync_refs_namespace}local/tags/*:refs/tags/*" "+${sync_refs_namespace}remote/heads/*:refs/heads/*" "+${sync_refs_namespace}remote/tags/*:refs/tags/*"
    git reset --hard
}

# Chain those funky functions together.
parse_args "$@" && check_sanity && prime_clean_up && preserve_local_refs && fetch_from_remote && reconcile
