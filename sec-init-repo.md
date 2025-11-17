# sec-init Repository Export (Mon 17 Nov 2025 23:11:42 AEDT)

## File: ./addons/espanso.sh
```
##https://espanso.org/docs/get-started/

wget https://github.com/espanso/espanso/releases/latest/download/espanso-debian-x11-amd64.deb
sudo apt install ./espanso-debian-x11-amd64.deb
# Register espanso as a systemd service (required only once)
espanso service register

# Start espanso
espanso start
```

## File: ./addons/signal_desktop.sh
```
# 1. Install our official public software signing key:
wget -O- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > signal-desktop-keyring.gpg;
cat signal-desktop-keyring.gpg | sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null

# 2. Add our repository to your list of repositories:
wget -O signal-desktop.sources https://updates.signal.org/static/desktop/apt/signal-desktop.sources;
cat signal-desktop.sources | sudo tee /etc/apt/sources.list.d/signal-desktop.sources > /dev/null

# 3. Update your package database and install Signal:
sudo apt update && sudo apt install signal-desktop
```

## File: ./addons/vscode.sh
```
#sudo apt update
#sudo apt install wget gpg

wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/ms_vscode.gpg >/dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ms_vscode.gpg] \
https://packages.microsoft.com/repos/vscode stable main" \
  | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

sudo apt update
sudo apt install code
```

## File: ./docs/CHANGELOG.md
```
# Changelog

## 0.1.0 (2025-03-30)
- Initial modular framework
- Modules: 00_preflight, 10_packages, 20_udev, 30_enrol, 40_pam, 50_crypttab, 60_dracut, 70_grub, 80_finish
- Introduced package list architecture (default + user + extra)
- Added documentation and run flow

```

## File: ./docs/secure-init-architecture.md
```
# secure-init System Architecture
## Technical Overview & Maintenance Guide

(Modified: sudo-hardening and finish logic combined into a single final module.)

## 0. Purpose
This repository implements a modular, reproducible bootstrap for Debian/Ubuntu systems using:
- YubiKey FIDO2
- PAM U2F authentication
- systemd-cryptenroll FIDO2 unlocking
- SSH resident FIDO2 keys
- GRUB password hardening
- udev, sudo, crypttab, initramfs, ufw tightening

The document explains how the system works so it can be safely maintained even if all chat history is lost.

## 1. Execution Model
`secure-init.sh`:
1. Logs all actions.
2. Discovers modules under `modules/`.
3. Executes them in ascending numeric order.
4. Executes the combined final module (`90_final.sh`) last.
5. Exports shared variables.
6. Stops immediately on any error.

## 2. Directory Structure
```
secure-init/
â”œâ”€â”€ secure-init.sh
â”œâ”€â”€ modules/
â”‚     â”œâ”€â”€ 00_preflight.sh
â”‚     â”œâ”€â”€ 10_packages.sh
â”‚     â”œâ”€â”€ 20_udev.sh
â”‚     â”œâ”€â”€ 30_enrol.sh
â”‚     â”œâ”€â”€ 40_pam.sh
â”‚     â”œâ”€â”€ 50_crypttab.sh
â”‚     â”œâ”€â”€ 60_initramfs.sh
â”‚     â”œâ”€â”€ 70_grub.sh
â”‚     â””â”€â”€ 90_final.sh   â† sudo-hardening + reboot handling
â””â”€â”€ packages.list
```

Numbered modules run in order; `90_final.sh` is always the last step.

## 3. Why Modules Are `sourced`
Modules are sourced so they share:
- Logging
- Error handling
- Environment variables
- State between modules

If executed in a subshell, information like enrolled key paths would not propagate.

## 4. Privilege Model
`secure-init.sh` **runs unprivileged**.

Modules use:
```
sudo <cmd>
```
only when needed. This ensures:
- YubiKey enrollment does not create root-owned files.
- SSH resident keys remain under `$HOME`.
- PAM and udev resources install atomically and safely.

Running the whole script under sudo would break enrollment and risk account lockout.

## 5. Module Responsibilities

### 00_preflight.sh
Validates:
- sudo availability
- required binaries
- correct user (non-root)
Creates environment and log file.

### 10_packages.sh
Installs:
- ufw
- libpam-u2f
- systemd-cryptsetup
- openssh
- keepassxc
- dracut (optional)

Idempotent.

### 20_udev.sh
Configures:
- YubiKey access rules
- plugdev group
- hidraw permissions

Ensures correct device ownership before enrollment.

### 30_enrol.sh
Handles:
- pamu2fcfg for both YubiKeys
- ssh-keygen -K for resident keys
- authorized_keys population
- systemd-cryptenroll for both keys

Must run as the normal user.

### 40_pam.sh
Enforces:
```
auth sufficient pam_u2f.so authfile=/etc/Yubico/u2f_keys cue
auth required   pam_deny.so
```
Inserted at the very top of:
- /etc/pam.d/common-auth
- /etc/pam.d/other

`pam_deny.so` must immediately follow pam_u2f.so.

### 50_crypttab.sh
Writes:
```
cryptroot UUID=<uuid> none luks,fido2-device=auto
```

Must precede initramfs rebuild.

### 60_initramfs.sh
Handles:
- dracut or initramfs-tools hooks
- fido2 + hid + usbhid inclusion
- rebuilds initramfs safely

### 70_grub.sh
- interactive password hashing
- writes 40_custom
- disables recovery entries
- updates GRUB safely

### 90_final.sh  (combined sudo hardening + reboot sequence)
Does two things:

#### 1. Installs sudo hardening:
```
Defaults timestamp_timeout=0
auth sufficient pam_u2f.so authfile=/etc/Yubico/u2f_keys cue
auth required   pam_deny.so
```
Installed via atomic sudoers.d file with visudo validation.

#### 2. Handles the final reboot
- Provides 10-second countdown
- User may cancel by pressing Enter
- Avoids sudo (timestamp likely expired)

This module **must always run last**.

## 6. Logging
All logs go to:
```
~/secure-init/secure-init.log
```
Never contains sensitive outputs.

## 7. Adding New Modules
Drop a file into `modules/`:
```
modules/25_firewall.sh
```
Rules:
- must be idempotent
- must not modify PAM, crypttab, GRUB unless explicitly intended
- must use `say` for logging
- must not require being run as root

## 8. Debugging
1. View logs:
```
cat ~/secure-init/secure-init.log
```
2. Re-run the entire script (safeâ€”modules are idempotent).
3. Run a single module:
```
source modules/40_pam.sh
```

## 9. Full Rebuild Workflow
1. Install Debian/Ubuntu.
2. Clone repo.
3. Run:
```
./secure-init.sh
```
4. Reboot.
5. System now uses:
   - FIDO2 LUKS unlock
   - PAM U2F-only login
   - SSH resident FIDO2 keys

## 10. Why This Document Exists
Written intentionally as a transfer-of-knowledge document for:
- future you
- future ChatGPT instances
- anyone maintaining the repo in the absence of session history

It ensures no part of the design is lost to time.
```

## File: ./.git/COMMIT_EDITMSG
```
Initial commit
```

## File: ./.git/config
```
[core]
	repositoryformatversion = 0
	filemode = true
	bare = false
	logallrefupdates = true
[remote "origin"]
	url = git@github.com:lcrisp/sec-init.git
	fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
	remote = origin
	merge = refs/heads/main
```

## File: ./.git/description
```
Unnamed repository; edit this file 'description' to name the repository.
```

## File: ./.git/HEAD
```
ref: refs/heads/main
```

## File: ./.git/hooks/applypatch-msg.sample
```
#!/bin/sh
#
# An example hook script to check the commit log message taken by
# applypatch from an e-mail message.
#
# The hook should exit with non-zero status after issuing an
# appropriate message if it wants to stop the commit.  The hook is
# allowed to edit the commit message file.
#
# To enable this hook, rename this file to "applypatch-msg".

. git-sh-setup
commitmsg="$(git rev-parse --git-path hooks/commit-msg)"
test -x "$commitmsg" && exec "$commitmsg" ${1+"$@"}
:
```

## File: ./.git/hooks/commit-msg.sample
```
#!/bin/sh
#
# An example hook script to check the commit log message.
# Called by "git commit" with one argument, the name of the file
# that has the commit message.  The hook should exit with non-zero
# status after issuing an appropriate message if it wants to stop the
# commit.  The hook is allowed to edit the commit message file.
#
# To enable this hook, rename this file to "commit-msg".

# Uncomment the below to add a Signed-off-by line to the message.
# Doing this in a hook is a bad idea in general, but the prepare-commit-msg
# hook is more suited to it.
#
# SOB=$(git var GIT_AUTHOR_IDENT | sed -n 's/^\(.*>\).*$/Signed-off-by: \1/p')
# grep -qs "^$SOB" "$1" || echo "$SOB" >> "$1"

# This example catches duplicate Signed-off-by lines.

test "" = "$(grep '^Signed-off-by: ' "$1" |
	 sort | uniq -c | sed -e '/^[ 	]*1[ 	]/d')" || {
	echo >&2 Duplicate Signed-off-by lines.
	exit 1
}
```

## File: ./.git/hooks/fsmonitor-watchman.sample
```
#!/usr/bin/perl

use strict;
use warnings;
use IPC::Open2;

# An example hook script to integrate Watchman
# (https://facebook.github.io/watchman/) with git to speed up detecting
# new and modified files.
#
# The hook is passed a version (currently 2) and last update token
# formatted as a string and outputs to stdout a new update token and
# all files that have been modified since the update token. Paths must
# be relative to the root of the working tree and separated by a single NUL.
#
# To enable this hook, rename this file to "query-watchman" and set
# 'git config core.fsmonitor .git/hooks/query-watchman'
#
my ($version, $last_update_token) = @ARGV;

# Uncomment for debugging
# print STDERR "$0 $version $last_update_token\n";

# Check the hook interface version
if ($version ne 2) {
	die "Unsupported query-fsmonitor hook version '$version'.\n" .
	    "Falling back to scanning...\n";
}

my $git_work_tree = get_working_dir();

my $retry = 1;

my $json_pkg;
eval {
	require JSON::XS;
	$json_pkg = "JSON::XS";
	1;
} or do {
	require JSON::PP;
	$json_pkg = "JSON::PP";
};

launch_watchman();

sub launch_watchman {
	my $o = watchman_query();
	if (is_work_tree_watched($o)) {
		output_result($o->{clock}, @{$o->{files}});
	}
}

sub output_result {
	my ($clockid, @files) = @_;

	# Uncomment for debugging watchman output
	# open (my $fh, ">", ".git/watchman-output.out");
	# binmode $fh, ":utf8";
	# print $fh "$clockid\n@files\n";
	# close $fh;

	binmode STDOUT, ":utf8";
	print $clockid;
	print "\0";
	local $, = "\0";
	print @files;
}

sub watchman_clock {
	my $response = qx/watchman clock "$git_work_tree"/;
	die "Failed to get clock id on '$git_work_tree'.\n" .
		"Falling back to scanning...\n" if $? != 0;

	return $json_pkg->new->utf8->decode($response);
}

sub watchman_query {
	my $pid = open2(\*CHLD_OUT, \*CHLD_IN, 'watchman -j --no-pretty')
	or die "open2() failed: $!\n" .
	"Falling back to scanning...\n";

	# In the query expression below we're asking for names of files that
	# changed since $last_update_token but not from the .git folder.
	#
	# To accomplish this, we're using the "since" generator to use the
	# recency index to select candidate nodes and "fields" to limit the
	# output to file names only. Then we're using the "expression" term to
	# further constrain the results.
	my $last_update_line = "";
	if (substr($last_update_token, 0, 1) eq "c") {
		$last_update_token = "\"$last_update_token\"";
		$last_update_line = qq[\n"since": $last_update_token,];
	}
	my $query = <<"	END";
		["query", "$git_work_tree", {$last_update_line
			"fields": ["name"],
			"expression": ["not", ["dirname", ".git"]]
		}]
	END

	# Uncomment for debugging the watchman query
	# open (my $fh, ">", ".git/watchman-query.json");
	# print $fh $query;
	# close $fh;

	print CHLD_IN $query;
	close CHLD_IN;
	my $response = do {local $/; <CHLD_OUT>};

	# Uncomment for debugging the watch response
	# open ($fh, ">", ".git/watchman-response.json");
	# print $fh $response;
	# close $fh;

	die "Watchman: command returned no output.\n" .
	"Falling back to scanning...\n" if $response eq "";
	die "Watchman: command returned invalid output: $response\n" .
	"Falling back to scanning...\n" unless $response =~ /^\{/;

	return $json_pkg->new->utf8->decode($response);
}

sub is_work_tree_watched {
	my ($output) = @_;
	my $error = $output->{error};
	if ($retry > 0 and $error and $error =~ m/unable to resolve root .* directory (.*) is not watched/) {
		$retry--;
		my $response = qx/watchman watch "$git_work_tree"/;
		die "Failed to make watchman watch '$git_work_tree'.\n" .
		    "Falling back to scanning...\n" if $? != 0;
		$output = $json_pkg->new->utf8->decode($response);
		$error = $output->{error};
		die "Watchman: $error.\n" .
		"Falling back to scanning...\n" if $error;

		# Uncomment for debugging watchman output
		# open (my $fh, ">", ".git/watchman-output.out");
		# close $fh;

		# Watchman will always return all files on the first query so
		# return the fast "everything is dirty" flag to git and do the
		# Watchman query just to get it over with now so we won't pay
		# the cost in git to look up each individual file.
		my $o = watchman_clock();
		$error = $output->{error};

		die "Watchman: $error.\n" .
		"Falling back to scanning...\n" if $error;

		output_result($o->{clock}, ("/"));
		$last_update_token = $o->{clock};

		eval { launch_watchman() };
		return 0;
	}

	die "Watchman: $error.\n" .
	"Falling back to scanning...\n" if $error;

	return 1;
}

sub get_working_dir {
	my $working_dir;
	if ($^O =~ 'msys' || $^O =~ 'cygwin') {
		$working_dir = Win32::GetCwd();
		$working_dir =~ tr/\\/\//;
	} else {
		require Cwd;
		$working_dir = Cwd::cwd();
	}

	return $working_dir;
}
```

## File: ./.git/hooks/post-update.sample
```
#!/bin/sh
#
# An example hook script to prepare a packed repository for use over
# dumb transports.
#
# To enable this hook, rename this file to "post-update".

exec git update-server-info
```

## File: ./.git/hooks/pre-applypatch.sample
```
#!/bin/sh
#
# An example hook script to verify what is about to be committed
# by applypatch from an e-mail message.
#
# The hook should exit with non-zero status after issuing an
# appropriate message if it wants to stop the commit.
#
# To enable this hook, rename this file to "pre-applypatch".

. git-sh-setup
precommit="$(git rev-parse --git-path hooks/pre-commit)"
test -x "$precommit" && exec "$precommit" ${1+"$@"}
:
```

## File: ./.git/hooks/pre-commit.sample
```
#!/bin/sh
#
# An example hook script to verify what is about to be committed.
# Called by "git commit" with no arguments.  The hook should
# exit with non-zero status after issuing an appropriate message if
# it wants to stop the commit.
#
# To enable this hook, rename this file to "pre-commit".

if git rev-parse --verify HEAD >/dev/null 2>&1
then
	against=HEAD
else
	# Initial commit: diff against an empty tree object
	against=$(git hash-object -t tree /dev/null)
fi

# If you want to allow non-ASCII filenames set this variable to true.
allownonascii=$(git config --type=bool hooks.allownonascii)

# Redirect output to stderr.
exec 1>&2

# Cross platform projects tend to avoid non-ASCII filenames; prevent
# them from being added to the repository. We exploit the fact that the
# printable range starts at the space character and ends with tilde.
if [ "$allownonascii" != "true" ] &&
	# Note that the use of brackets around a tr range is ok here, (it's
	# even required, for portability to Solaris 10's /usr/bin/tr), since
	# the square bracket bytes happen to fall in the designated range.
	test $(git diff-index --cached --name-only --diff-filter=A -z $against |
	  LC_ALL=C tr -d '[ -~]\0' | wc -c) != 0
then
	cat <<\EOF
Error: Attempt to add a non-ASCII file name.

This can cause problems if you want to work with people on other platforms.

To be portable it is advisable to rename the file.

If you know what you are doing you can disable this check using:

  git config hooks.allownonascii true
EOF
	exit 1
fi

# If there are whitespace errors, print the offending file names and fail.
exec git diff-index --check --cached $against --
```

## File: ./.git/hooks/pre-merge-commit.sample
```
#!/bin/sh
#
# An example hook script to verify what is about to be committed.
# Called by "git merge" with no arguments.  The hook should
# exit with non-zero status after issuing an appropriate message to
# stderr if it wants to stop the merge commit.
#
# To enable this hook, rename this file to "pre-merge-commit".

. git-sh-setup
test -x "$GIT_DIR/hooks/pre-commit" &&
        exec "$GIT_DIR/hooks/pre-commit"
:
```

## File: ./.git/hooks/prepare-commit-msg.sample
```
#!/bin/sh
#
# An example hook script to prepare the commit log message.
# Called by "git commit" with the name of the file that has the
# commit message, followed by the description of the commit
# message's source.  The hook's purpose is to edit the commit
# message file.  If the hook fails with a non-zero status,
# the commit is aborted.
#
# To enable this hook, rename this file to "prepare-commit-msg".

# This hook includes three examples. The first one removes the
# "# Please enter the commit message..." help message.
#
# The second includes the output of "git diff --name-status -r"
# into the message, just before the "git status" output.  It is
# commented because it doesn't cope with --amend or with squashed
# commits.
#
# The third example adds a Signed-off-by line to the message, that can
# still be edited.  This is rarely a good idea.

COMMIT_MSG_FILE=$1
COMMIT_SOURCE=$2
SHA1=$3

/usr/bin/perl -i.bak -ne 'print unless(m/^. Please enter the commit message/..m/^#$/)' "$COMMIT_MSG_FILE"

# case "$COMMIT_SOURCE,$SHA1" in
#  ,|template,)
#    /usr/bin/perl -i.bak -pe '
#       print "\n" . `git diff --cached --name-status -r`
# 	 if /^#/ && $first++ == 0' "$COMMIT_MSG_FILE" ;;
#  *) ;;
# esac

# SOB=$(git var GIT_COMMITTER_IDENT | sed -n 's/^\(.*>\).*$/Signed-off-by: \1/p')
# git interpret-trailers --in-place --trailer "$SOB" "$COMMIT_MSG_FILE"
# if test -z "$COMMIT_SOURCE"
# then
#   /usr/bin/perl -i.bak -pe 'print "\n" if !$first_line++' "$COMMIT_MSG_FILE"
# fi
```

## File: ./.git/hooks/pre-push.sample
```
#!/bin/sh

# An example hook script to verify what is about to be pushed.  Called by "git
# push" after it has checked the remote status, but before anything has been
# pushed.  If this script exits with a non-zero status nothing will be pushed.
#
# This hook is called with the following parameters:
#
# $1 -- Name of the remote to which the push is being done
# $2 -- URL to which the push is being done
#
# If pushing without using a named remote those arguments will be equal.
#
# Information about the commits which are being pushed is supplied as lines to
# the standard input in the form:
#
#   <local ref> <local oid> <remote ref> <remote oid>
#
# This sample shows how to prevent push of commits where the log message starts
# with "WIP" (work in progress).

remote="$1"
url="$2"

zero=$(git hash-object --stdin </dev/null | tr '[0-9a-f]' '0')

while read local_ref local_oid remote_ref remote_oid
do
	if test "$local_oid" = "$zero"
	then
		# Handle delete
		:
	else
		if test "$remote_oid" = "$zero"
		then
			# New branch, examine all commits
			range="$local_oid"
		else
			# Update to existing branch, examine new commits
			range="$remote_oid..$local_oid"
		fi

		# Check for WIP commit
		commit=$(git rev-list -n 1 --grep '^WIP' "$range")
		if test -n "$commit"
		then
			echo >&2 "Found WIP commit in $local_ref, not pushing"
			exit 1
		fi
	fi
done

exit 0
```

## File: ./.git/hooks/pre-rebase.sample
```
#!/bin/sh
#
# Copyright (c) 2006, 2008 Junio C Hamano
#
# The "pre-rebase" hook is run just before "git rebase" starts doing
# its job, and can prevent the command from running by exiting with
# non-zero status.
#
# The hook is called with the following parameters:
#
# $1 -- the upstream the series was forked from.
# $2 -- the branch being rebased (or empty when rebasing the current branch).
#
# This sample shows how to prevent topic branches that are already
# merged to 'next' branch from getting rebased, because allowing it
# would result in rebasing already published history.

publish=next
basebranch="$1"
if test "$#" = 2
then
	topic="refs/heads/$2"
else
	topic=`git symbolic-ref HEAD` ||
	exit 0 ;# we do not interrupt rebasing detached HEAD
fi

case "$topic" in
refs/heads/??/*)
	;;
*)
	exit 0 ;# we do not interrupt others.
	;;
esac

# Now we are dealing with a topic branch being rebased
# on top of master.  Is it OK to rebase it?

# Does the topic really exist?
git show-ref -q "$topic" || {
	echo >&2 "No such branch $topic"
	exit 1
}

# Is topic fully merged to master?
not_in_master=`git rev-list --pretty=oneline ^master "$topic"`
if test -z "$not_in_master"
then
	echo >&2 "$topic is fully merged to master; better remove it."
	exit 1 ;# we could allow it, but there is no point.
fi

# Is topic ever merged to next?  If so you should not be rebasing it.
only_next_1=`git rev-list ^master "^$topic" ${publish} | sort`
only_next_2=`git rev-list ^master           ${publish} | sort`
if test "$only_next_1" = "$only_next_2"
then
	not_in_topic=`git rev-list "^$topic" master`
	if test -z "$not_in_topic"
	then
		echo >&2 "$topic is already up to date with master"
		exit 1 ;# we could allow it, but there is no point.
	else
		exit 0
	fi
else
	not_in_next=`git rev-list --pretty=oneline ^${publish} "$topic"`
	/usr/bin/perl -e '
		my $topic = $ARGV[0];
		my $msg = "* $topic has commits already merged to public branch:\n";
		my (%not_in_next) = map {
			/^([0-9a-f]+) /;
			($1 => 1);
		} split(/\n/, $ARGV[1]);
		for my $elem (map {
				/^([0-9a-f]+) (.*)$/;
				[$1 => $2];
			} split(/\n/, $ARGV[2])) {
			if (!exists $not_in_next{$elem->[0]}) {
				if ($msg) {
					print STDERR $msg;
					undef $msg;
				}
				print STDERR " $elem->[1]\n";
			}
		}
	' "$topic" "$not_in_next" "$not_in_master"
	exit 1
fi

<<\DOC_END

This sample hook safeguards topic branches that have been
published from being rewound.

The workflow assumed here is:

 * Once a topic branch forks from "master", "master" is never
   merged into it again (either directly or indirectly).

 * Once a topic branch is fully cooked and merged into "master",
   it is deleted.  If you need to build on top of it to correct
   earlier mistakes, a new topic branch is created by forking at
   the tip of the "master".  This is not strictly necessary, but
   it makes it easier to keep your history simple.

 * Whenever you need to test or publish your changes to topic
   branches, merge them into "next" branch.

The script, being an example, hardcodes the publish branch name
to be "next", but it is trivial to make it configurable via
$GIT_DIR/config mechanism.

With this workflow, you would want to know:

(1) ... if a topic branch has ever been merged to "next".  Young
    topic branches can have stupid mistakes you would rather
    clean up before publishing, and things that have not been
    merged into other branches can be easily rebased without
    affecting other people.  But once it is published, you would
    not want to rewind it.

(2) ... if a topic branch has been fully merged to "master".
    Then you can delete it.  More importantly, you should not
    build on top of it -- other people may already want to
    change things related to the topic as patches against your
    "master", so if you need further changes, it is better to
    fork the topic (perhaps with the same name) afresh from the
    tip of "master".

Let's look at this example:

		   o---o---o---o---o---o---o---o---o---o "next"
		  /       /           /           /
		 /   a---a---b A     /           /
		/   /               /           /
	       /   /   c---c---c---c B         /
	      /   /   /             \         /
	     /   /   /   b---b C     \       /
	    /   /   /   /             \     /
    ---o---o---o---o---o---o---o---o---o---o---o "master"


A, B and C are topic branches.

 * A has one fix since it was merged up to "next".

 * B has finished.  It has been fully merged up to "master" and "next",
   and is ready to be deleted.

 * C has not merged to "next" at all.

We would want to allow C to be rebased, refuse A, and encourage
B to be deleted.

To compute (1):

	git rev-list ^master ^topic next
	git rev-list ^master        next

	if these match, topic has not merged in next at all.

To compute (2):

	git rev-list master..topic

	if this is empty, it is fully merged to "master".

DOC_END
```

## File: ./.git/hooks/pre-receive.sample
```
#!/bin/sh
#
# An example hook script to make use of push options.
# The example simply echoes all push options that start with 'echoback='
# and rejects all pushes when the "reject" push option is used.
#
# To enable this hook, rename this file to "pre-receive".

if test -n "$GIT_PUSH_OPTION_COUNT"
then
	i=0
	while test "$i" -lt "$GIT_PUSH_OPTION_COUNT"
	do
		eval "value=\$GIT_PUSH_OPTION_$i"
		case "$value" in
		echoback=*)
			echo "echo from the pre-receive-hook: ${value#*=}" >&2
			;;
		reject)
			exit 1
		esac
		i=$((i + 1))
	done
fi
```

## File: ./.git/hooks/push-to-checkout.sample
```
#!/bin/sh

# An example hook script to update a checked-out tree on a git push.
#
# This hook is invoked by git-receive-pack(1) when it reacts to git
# push and updates reference(s) in its repository, and when the push
# tries to update the branch that is currently checked out and the
# receive.denyCurrentBranch configuration variable is set to
# updateInstead.
#
# By default, such a push is refused if the working tree and the index
# of the remote repository has any difference from the currently
# checked out commit; when both the working tree and the index match
# the current commit, they are updated to match the newly pushed tip
# of the branch. This hook is to be used to override the default
# behaviour; however the code below reimplements the default behaviour
# as a starting point for convenient modification.
#
# The hook receives the commit with which the tip of the current
# branch is going to be updated:
commit=$1

# It can exit with a non-zero status to refuse the push (when it does
# so, it must not modify the index or the working tree).
die () {
	echo >&2 "$*"
	exit 1
}

# Or it can make any necessary changes to the working tree and to the
# index to bring them to the desired state when the tip of the current
# branch is updated to the new commit, and exit with a zero status.
#
# For example, the hook can simply run git read-tree -u -m HEAD "$1"
# in order to emulate git fetch that is run in the reverse direction
# with git push, as the two-tree form of git read-tree -u -m is
# essentially the same as git switch or git checkout that switches
# branches while keeping the local changes in the working tree that do
# not interfere with the difference between the branches.

# The below is a more-or-less exact translation to shell of the C code
# for the default behaviour for git's push-to-checkout hook defined in
# the push_to_deploy() function in builtin/receive-pack.c.
#
# Note that the hook will be executed from the repository directory,
# not from the working tree, so if you want to perform operations on
# the working tree, you will have to adapt your code accordingly, e.g.
# by adding "cd .." or using relative paths.

if ! git update-index -q --ignore-submodules --refresh
then
	die "Up-to-date check failed"
fi

if ! git diff-files --quiet --ignore-submodules --
then
	die "Working directory has unstaged changes"
fi

# This is a rough translation of:
#
#   head_has_history() ? "HEAD" : EMPTY_TREE_SHA1_HEX
if git cat-file -e HEAD 2>/dev/null
then
	head=HEAD
else
	head=$(git hash-object -t tree --stdin </dev/null)
fi

if ! git diff-index --quiet --cached --ignore-submodules $head --
then
	die "Working directory has staged changes"
fi

if ! git read-tree -u -m "$commit"
then
	die "Could not update working tree to new HEAD"
fi
```

## File: ./.git/hooks/sendemail-validate.sample
```
#!/bin/sh

# An example hook script to validate a patch (and/or patch series) before
# sending it via email.
#
# The hook should exit with non-zero status after issuing an appropriate
# message if it wants to prevent the email(s) from being sent.
#
# To enable this hook, rename this file to "sendemail-validate".
#
# By default, it will only check that the patch(es) can be applied on top of
# the default upstream branch without conflicts in a secondary worktree. After
# validation (successful or not) of the last patch of a series, the worktree
# will be deleted.
#
# The following config variables can be set to change the default remote and
# remote ref that are used to apply the patches against:
#
#   sendemail.validateRemote (default: origin)
#   sendemail.validateRemoteRef (default: HEAD)
#
# Replace the TODO placeholders with appropriate checks according to your
# needs.

validate_cover_letter () {
	file="$1"
	# TODO: Replace with appropriate checks (e.g. spell checking).
	true
}

validate_patch () {
	file="$1"
	# Ensure that the patch applies without conflicts.
	git am -3 "$file" || return
	# TODO: Replace with appropriate checks for this patch
	# (e.g. checkpatch.pl).
	true
}

validate_series () {
	# TODO: Replace with appropriate checks for the whole series
	# (e.g. quick build, coding style checks, etc.).
	true
}

# main -------------------------------------------------------------------------

if test "$GIT_SENDEMAIL_FILE_COUNTER" = 1
then
	remote=$(git config --default origin --get sendemail.validateRemote) &&
	ref=$(git config --default HEAD --get sendemail.validateRemoteRef) &&
	worktree=$(mktemp --tmpdir -d sendemail-validate.XXXXXXX) &&
	git worktree add -fd --checkout "$worktree" "refs/remotes/$remote/$ref" &&
	git config --replace-all sendemail.validateWorktree "$worktree"
else
	worktree=$(git config --get sendemail.validateWorktree)
fi || {
	echo "sendemail-validate: error: failed to prepare worktree" >&2
	exit 1
}

unset GIT_DIR GIT_WORK_TREE
cd "$worktree" &&

if grep -q "^diff --git " "$1"
then
	validate_patch "$1"
else
	validate_cover_letter "$1"
fi &&

if test "$GIT_SENDEMAIL_FILE_COUNTER" = "$GIT_SENDEMAIL_FILE_TOTAL"
then
	git config --unset-all sendemail.validateWorktree &&
	trap 'git worktree remove -ff "$worktree"' EXIT &&
	validate_series
fi
```

## File: ./.git/hooks/update.sample
```
#!/bin/sh
#
# An example hook script to block unannotated tags from entering.
# Called by "git receive-pack" with arguments: refname sha1-old sha1-new
#
# To enable this hook, rename this file to "update".
#
# Config
# ------
# hooks.allowunannotated
#   This boolean sets whether unannotated tags will be allowed into the
#   repository.  By default they won't be.
# hooks.allowdeletetag
#   This boolean sets whether deleting tags will be allowed in the
#   repository.  By default they won't be.
# hooks.allowmodifytag
#   This boolean sets whether a tag may be modified after creation. By default
#   it won't be.
# hooks.allowdeletebranch
#   This boolean sets whether deleting branches will be allowed in the
#   repository.  By default they won't be.
# hooks.denycreatebranch
#   This boolean sets whether remotely creating branches will be denied
#   in the repository.  By default this is allowed.
#

# --- Command line
refname="$1"
oldrev="$2"
newrev="$3"

# --- Safety check
if [ -z "$GIT_DIR" ]; then
	echo "Don't run this script from the command line." >&2
	echo " (if you want, you could supply GIT_DIR then run" >&2
	echo "  $0 <ref> <oldrev> <newrev>)" >&2
	exit 1
fi

if [ -z "$refname" -o -z "$oldrev" -o -z "$newrev" ]; then
	echo "usage: $0 <ref> <oldrev> <newrev>" >&2
	exit 1
fi

# --- Config
allowunannotated=$(git config --type=bool hooks.allowunannotated)
allowdeletebranch=$(git config --type=bool hooks.allowdeletebranch)
denycreatebranch=$(git config --type=bool hooks.denycreatebranch)
allowdeletetag=$(git config --type=bool hooks.allowdeletetag)
allowmodifytag=$(git config --type=bool hooks.allowmodifytag)

# check for no description
projectdesc=$(sed -e '1q' "$GIT_DIR/description")
case "$projectdesc" in
"Unnamed repository"* | "")
	echo "*** Project description file hasn't been set" >&2
	exit 1
	;;
esac

# --- Check types
# if $newrev is 0000...0000, it's a commit to delete a ref.
zero=$(git hash-object --stdin </dev/null | tr '[0-9a-f]' '0')
if [ "$newrev" = "$zero" ]; then
	newrev_type=delete
else
	newrev_type=$(git cat-file -t $newrev)
fi

case "$refname","$newrev_type" in
	refs/tags/*,commit)
		# un-annotated tag
		short_refname=${refname##refs/tags/}
		if [ "$allowunannotated" != "true" ]; then
			echo "*** The un-annotated tag, $short_refname, is not allowed in this repository" >&2
			echo "*** Use 'git tag [ -a | -s ]' for tags you want to propagate." >&2
			exit 1
		fi
		;;
	refs/tags/*,delete)
		# delete tag
		if [ "$allowdeletetag" != "true" ]; then
			echo "*** Deleting a tag is not allowed in this repository" >&2
			exit 1
		fi
		;;
	refs/tags/*,tag)
		# annotated tag
		if [ "$allowmodifytag" != "true" ] && git rev-parse $refname > /dev/null 2>&1
		then
			echo "*** Tag '$refname' already exists." >&2
			echo "*** Modifying a tag is not allowed in this repository." >&2
			exit 1
		fi
		;;
	refs/heads/*,commit)
		# branch
		if [ "$oldrev" = "$zero" -a "$denycreatebranch" = "true" ]; then
			echo "*** Creating a branch is not allowed in this repository" >&2
			exit 1
		fi
		;;
	refs/heads/*,delete)
		# delete branch
		if [ "$allowdeletebranch" != "true" ]; then
			echo "*** Deleting a branch is not allowed in this repository" >&2
			exit 1
		fi
		;;
	refs/remotes/*,commit)
		# tracking branch
		;;
	refs/remotes/*,delete)
		# delete tracking branch
		if [ "$allowdeletebranch" != "true" ]; then
			echo "*** Deleting a tracking branch is not allowed in this repository" >&2
			exit 1
		fi
		;;
	*)
		# Anything else (is there anything else?)
		echo "*** Update hook: unknown type of update to ref $refname of type $newrev_type" >&2
		exit 1
		;;
esac

# --- Finished
exit 0
```

## File: ./.gitignore
```
.ssh/
*.swp
```

## File: ./.git/index
```
DIRC      i›]ïi›]ï  ş (…s  ¤  è  è   «ñ7ŠıDÜÏ‰Ì&5Yİ)VQ 
.gitignore        i²49²~i²49²~  ş (Cm  ¤  è  è   n‹÷:¥PÔÅo5ƒÍÇ¤¦/8 .version  iq»2i–iq»2i–  ş («  ¤  è  è  ,Õ\ŸîZ1×?€´iŞœ D•ù:! addons/espanso.sh ip3-"éüip3-"éü  ş (=8  ¤  è  è  jô­ÖìÇ¸d¤â0““ÄìÔ6 addons/signal_desktop.sh  i²Æ4ãBi²}8  ş (…à  ¤  è  è  ™™½è‹nÌ^g9ı)¶}7èJ docs/CHANGELOG.md i²Æ4ãBi’Ù-ÍW¬  ş (J9  ¤  è  è  6eXZb9j?ÓGgLîÙ™4  docs/secure-init-architecture.md  i³38Ü¾i³38Ü¾  ş * ¦  ¤  è  è   J6¶S
wDé¸È¡ q_ı¢éZÔE lists/package.list        i¥¥hIlihİ!Ô¦  ş (–  í  è  è  öò6š¿i¼3ùÇ—OÌñGî°±‚ modules/00_preflight.sh   i¥¥hIlik¸2ù  ş (A{  í  è  è  •lkg&É(õ	:î1ªqÈ4zs modules/10_packages.sh    i¥¥hIlir ‡a‚  ş (Ç  í  è  è  lVĞ¿¸¬!ÏÎ0ŠO+d£öL modules/20_udev.sh        i¥¥hIlisfÍ]  ş (Aˆ  í  è  è  	H‰#Ú¤ƒ<AÚë\|šÇc1 modules/30_enroll.sh      i¥¥hIli€ßo¢¶  ş (D©  í  è  è  îF8)-
sÌtû2&a3rIş modules/40_pam.sh i¥¥hIliH[¾Ä  ş (Dª  í  è  è  ıFúlè.< q»ƒpúIø‰}ÀŸ1 modules/50_crypttab.sh    i¥¥hIliÇ.«ú  ş (|m  í  è  è  ]øÄmı·CEš—ßhÏ@²{l¿Ø< modules/60_initramfs.sh   i¥¥hIli!zk  ş (p  í  è  è  	¨ò%\DèŸ[q°?¤»ƒ¨ã>ŒÕ modules/70_grub.sh        i¥¥hIlivş%eğ©  ş (ƒû  í  è  è  ½Ui@«íÎkş¨ín
0(Ú£“Óç modules/80_sudo.sh        i¥¥hIli}7s	  ş („e  í  è  è  T?@Ú¶)Ji1ê[yòù°i8 modules/finish.sh i‘ T"ivş%eğ©  ş * '  ¤  è  è  ½Ui@«íÎkş¨ín
0(Ú£“Óç old/80_sudo.sh    i¥+Ñ’i‘oÿ¬  ş („  í  è  è  z»W1#øCÉ¨>Ìh„¼+ÂÕ¬‘ secure-init.sh    TREE   ± 19 5
¸‰~Û´AÚ8ğ<¥šÀòÃ‡$old 1 0
Ö
É†\›¦a®àÆíƒq“Ÿû´!docs 2 0
E×…EÁ.|&>é	¡×¨‘³ú(Ílists 1 0
8+<¸Ò O*u¹ªbªân»addons 2 0
^Eæ’N;ó›­š‹&¡¨¿5ªmodules 10 0
&Â ƒŞìİ“€Á»Š½$êŠ`SêU‰n’Ú‚ÚÓnüÓS³C¼«```

## File: ./.git/info/exclude
```
# git ls-files --others --exclude-from=.git/info/exclude
# Lines that start with '#' are comments.
# For a project mostly in C, the following would be a good set of
# exclude patterns (uncomment them if you want to use them):
# *.[oa]
# *~
```

## File: ./.git/logs/HEAD
```
0000000000000000000000000000000000000000 64433ebcc2816b71f19ce90760c873e0f1915f5d lcrisp <llcrisp49@gmail.com> 1763351419 +1100	commit (initial): Initial commit
64433ebcc2816b71f19ce90760c873e0f1915f5d 0000000000000000000000000000000000000000 lcrisp <llcrisp49@gmail.com> 1763353868 +1100	Branch: renamed refs/heads/main to refs/heads/main
64433ebcc2816b71f19ce90760c873e0f1915f5d 64433ebcc2816b71f19ce90760c873e0f1915f5d lcrisp <llcrisp49@gmail.com> 1763353868 +1100	Branch: renamed refs/heads/main to refs/heads/main
64433ebcc2816b71f19ce90760c873e0f1915f5d 98cf770a2cdc4418c35005d801ef2224b047c144 lcrisp <llcrisp49@gmail.com> 1763358554 +1100	commit: Initial commit: full modular secure-init framework
```

## File: ./.git/logs/refs/heads/main
```
0000000000000000000000000000000000000000 64433ebcc2816b71f19ce90760c873e0f1915f5d lcrisp <llcrisp49@gmail.com> 1763351419 +1100	commit (initial): Initial commit
64433ebcc2816b71f19ce90760c873e0f1915f5d 64433ebcc2816b71f19ce90760c873e0f1915f5d lcrisp <llcrisp49@gmail.com> 1763353868 +1100	Branch: renamed refs/heads/main to refs/heads/main
64433ebcc2816b71f19ce90760c873e0f1915f5d 98cf770a2cdc4418c35005d801ef2224b047c144 lcrisp <llcrisp49@gmail.com> 1763358554 +1100	commit: Initial commit: full modular secure-init framework
```

## File: ./.git/logs/refs/remotes/origin/main
```
0000000000000000000000000000000000000000 98cf770a2cdc4418c35005d801ef2224b047c144 lcrisp <llcrisp49@gmail.com> 1763359080 +1100	update by push
```

## File: ./.git/objects/06/f4add6ecc7b864a490e2309393c4ec05d43614
```
x}RMkÃ0İ9¿BPè-6İ`Œ;î´ÃØPlÕ5õbc)+…ıø9N[H(½ZOOïÃ]ˆ<o^V°QğÑ³`‡q·óÆc€4tÁà¸“#fö®÷½ƒ¶ÍÑ‘@ûÙÂ^$ñVë!Yb5¢0¨˜¶Ä‰Ic]–X!ø—´­%Ì?1Ã[åÅP*º-È\Î¨{mÊy!ãÁF"ĞgÍû"t¼52°´Üb.g‹¼_İ!4Í
¼[[ıgJ‘½Ä|‰p#	¥ä×‘'¾F°Ğ§¸lâ{Á”°Å›Y>s©’[\f3ó$¦Æ|>®FÅÊ.¸n.Ì?)ø®íMnš:‚Ò'vÈØ[ğçòUëİ65÷R,L½Ãz=U1>]°sOÍ?ıŠá*```

## File: ./.git/objects/0b/8923da8d05a4833c41daeb5c7c9ac712816331
```
xÅVïOãFígÿs{¡@‹cbtw*$z„Ş‰ÒC„œt¢(rìq²Š³ëz×¨ÑÁÿŞ™õ˜6 ûP©ù”ìNŞÌ¼yoìi¦§¼{ûİëWAiŠ`*U€ê¦‘™{¯áR'e†‡p°?AUè,ë»ã«²Èµ¡ó±’©ÄªË%*:…/åT^àÊ@ª¸:½„qx¾£Ñ(ĞÈ„£t½‘Jà·ñÅˆ2İÌ¥¥KôÍè²ˆ	xºƒqY /•´œİ3hÁÇRC.sL#™y&Zíì~Œçšn@ü¡n¡·“DaûÇ­sØºÙŞ…;èı àÑSˆ	‡Çz¹äü{½€“ Áû@•YáÉ÷xx€S\Jc¤šÅş%-ŠÑ89ˆÛƒı»–Œºı.)ÆF…%áQ«¾ïÃ5şYÊ™1Ã®*È£e¦q:«~3÷‰¨ªú÷ÊX\&~\¬r[QŞàš”G9S
ÔŒŒÑaQ›Eb¨,Åtï­®ë„ìÏú{àX0It°{Â…NÎ†Ÿ9Ïç(“Ôšx0Öx··àO‰BFåPww]òÎªB”¶T\©b±íÉ†ÊĞ¨i2*•3Hˆ ØêB¢aÎõ–:Ÿé}øt9úUdÀŒÇZ´ÇDœğâ9É	Şíï·Ç/E×s9ÿx=º‹áGœ›íGE¼Z¨nšÙ²prR³Ÿ§'}áÕ4s#,úµ'<§Lñ+*,"–¤²0v=nŠµÅªß'3ƒ<+gD1ø1ˆVpÛ›šH0vÓvÓñÛç:nC
ÿiGÈIùŞZrà_ğmQ¢çzŸ\9½Œ;°-©Ìu “	&á›7ƒŸ&fÑÏKÖC5¡ö:NLÔ\†¯=ÀÜÉS9Çqº]áÉXVŠ`¾¶ÉıGÖÖØ99èC[
©¤uÈç~î2Î+¥pĞipµ+RÌ€Êäõµï›~»ù{›şYÎù<N5ûÓ$¡mVi¨»Éë^*Y<ÎV/Pu5ä´8tK˜TA5r”Š|Ìÿ«4T&Ì¿—±Ù:ôÊD‡~eæã¨´š“órßúıl£ê«&ï‹6¨;ÏsT	—L‹\³m¢zÉ}“êÿ[Ùo–wÕÔÿ¥ïuöÍYáë ®Ä+›ˆK<ğê˜&\Éı‰Mºr®C;ölì¾h‡.Æº˜` —=Á`]_T€OŞÈ4ÎĞäÊ ïu¾r+6•‚Ó~E1z†…/=mé!îŸ¯‰ñhx-ÀïìÕ%|Ã„ m\?YÚÍÙ}ÜW^tï<ô*‘gh‘ö÷ß¿íßa```

## File: ./.git/objects/14/3665585a160b6239136a3fd347674ceed99934
```
xµXMoGİóüŠ¼XH†¤ÛI¼q ­%Û‚#[¬{"{fzÈgº'ıAš{X{Øs:æ×ù—ì«î’”ä´APœî®W¯^½bÑ˜‚>?şö/ÈÉ2X™+­<]oœ—-Ør¡¼,=dÑGY.´*ECVÒ®”\ÓßèB(í¥º”ô&¨JfÙÁ…©T­dõ‚\¨L¾¶’Zé9	]Q#Ü‚3W%•¦-”–aC‚V5’×à”ÖT¡‘£ÃŒŸŒè2ØÎ8™}\(GVâ³òÆnHµ]#[©½Ãñ%axÅ¥*°aaŒwŞŠjcéTJèñM´äb´ş"ËéŸ¡Pïä†^ŸŸ~8Æß—'tsüšDğœ¼2Ò›U^ÚM¬išôİ˜r‰ı°êúú-.ã öıã¥Ü8<ysuóê„skc+ÚÂ„'¡’«£ˆŞÅİ½( ’Bmí(Ôkòj¾À±|
0‘T™20$?wÒâha°
OÒE	Ç,9CÈq)4x"jÙl¨å,â?dB®¤&U“@0åBxÚ	f‡¤9?Šéx2¢³Ï #AÈ·l²Ù…Fn1{‘aÑf¬`+QòR7ÊGtª\i@!×§ØëJZš¥Œ»ñl”}= ‡Ğ"x®”ºB¼¤¨€›´£ìéİÅ;Zí‰fßM¦ñ¾Ş!5‚£yÆïvÆ‚=) +a• kpÙç#ºö¦sàX++%<ƒ…ˆ…Ş´Öàl&gŒÉ¢R˜×Ş†T3³Ù,Ûeœ}¹ıíËí/øw¿Üp™½øê?ÄÿìŞ™L¦•uÃiO/İ_ñ+D¹sÜ=îzÁñdÊÔzøá×“i$ñÃOŸòŞíÃÏM¦K^ğ|2İ’÷áßL¦sŠ»o{´öòÆˆü÷×ûÂò*ŒkE¤«†+âËíğò‘DÎ8'ÙûĞ’Sİ£M6€ó:Ñéït‡'±ÍZl"#iòØ¥Ìƒ¦Ÿ® H•ƒdJš9l)«Y6|V¡êâ—\} ó&qÕ2OBqÆ„ÚEÓ™^)kt¬é-)YQ<ˆˆêõk‰ZícÈ²ó•Ï5õ”Õ4n!›†•º×Fİ¢F-%%µÂBH$È/Ô!4i€áìÄg¤Q]—V­T#çòwj?„\Çİ°²zü¯'_Dì¹#Ğ÷e[ıÿ4µ†¬’–²’Õˆ¢ºKíĞtÜ¾§G,*¨ù¢¥•Œ„Eæs³fõªqKÔí=Õe½CXå©ùëÛgĞ™$ïÜ˜¸0X¨c¢PñÚù(\Ş´ÜôpO^•‘]{ëëzaĞd\iUçûbœ	Ò·\öˆÇûó>V¹%D±4èAĞÕriB/­¤„]I×A3U¡å•t¬5è„÷dà'Ñ¨
0D´â±b%T#â[håÏA1ÛÑj!mØ'‡BZÖ+4=èî6:g³WQ‡Ûî¨Ç×E»ØFF<¢{Bs°Š7@gÂş* y8®ñÇ>é¤¾4’‘ÊAAÉMğs‰Ï• 0˜Û…hĞüÏ+Ùv.áµİ‰Ø+£k5¿OÀ*Î%‰=»&Ì9·skâÉ…SÖÔIÛ*ç¸+eÙY"Ü¬Wp4L*ëªCµ¡‚†ºá,öHì‹æ[ …#™µ±—5PCMÆ/[Á7BÜ989íówqÅÖ ôÖ€½†±ê_²šFòv¦Íùí1qƒì"8UM$ÙÒ\şMLwñŸ±8 ±T |2”£®U©ØL ’)BA¸øØË±ôå˜mRiÆx–®X™Å—·|£ø2|ÏoÇrQ¤e}‚¯àÂ	Ø,™šQ‹ûr—©Æp†-XÉŞ} (¥Í²ß«ßzF-‡»ß£kx1˜Ÿİåû¨ïuªO·<v0®º¹9?}ù}€›ı2£%5aéjU™ã<ã%î•"JH£/Cñ%D£whÜ‚jªşØûıo)=ãÁ’íË¹7¦a÷f–Ì–x0}#VáÿÁüAé²c>´?‹5k8>ÉTŒ½Öšc‰—¨1¯Vèl­'8Íê:B G	HM‹ã+å¢BHÑµÁùhßËHè¢ò$'»æ}°µùQ¶FÑômÛA¢$FˆÃì”µİ¯¹KâFHkgDƒÈÄŞ¿sË‰µ§²¡‡óª•î¶›ò'ˆêËIbåÿ‘ÒÜ'Àé•à5w‹xEÇ(5$Z+ÔÔJÅèWI®‘¹Äè{>ÄšH5ø/­YavpĞÜfÒ@ŒcÓ¨ Mx|ÃŞŠúR6T CLx–@®±ædeT{Ë­÷`P4èj˜¸;@icëMv=ÖTï|Ø±]=é€/|Ë	Ì=ºƒ£9rfR6ş=Ş·½{ŸGX…à=Æ‹@âÔ«¡ Å“ÈX<Z8ûêoFtREÃÿÃfï%²SØ¸V"¦³Ù›Òñ)7>~»oåéa_ÉÖïŠ{KMŒ í»Ëğ%ì êO~ûóWœ×0Úqsá
é —æ—jØ =&PlfQÙqïïâ‘¼{/è)œ%Æ*ÍÊƒşÄ#½ŞÿÄƒ6#œ‚ÃôI/&’+™óÖ,³(Xà0”.Ô/¿Üö0ÛÓ‡qö‚»Ùãia:>Ù£Átw]$käì»½àÄU@ú„¡³†ó4Ø—ğİ<„¯ÖYê‡ãÓq£}&I„!ÅîÀ+No×é×
¹ò@	#BŞÚ?Ş¼»†!c•¾îgù<úN€ªtúş÷†tfáüöÀ&?–Çé0dŸ}Æ8á2î H"Aò,ìù§ÌêÚÕÒæ¦Î—¸4z;¥£é2ëÀ¿¯ĞÆ„İ¯0w¿¹üˆM!e(kî9¢aRgæpj2¬‹ŸE:b×R£ ¢³†w¸(ü,Ğ{m üÖó2ŞÚ¢æ ÷¨á¨¡£ì¤_X```

## File: ./.git/objects/1c/29f62422000265cf26280a41abcb3ec3186a10
```
x+)JMU026b040031QĞKÏ,ÉLÏË/JeXÍûÑ¼ë¯ËógÔL#ïj2…ñš BbJJ~^1Cœ+ó³I~ÖŸg¯ÕÛ­¶pÅ~ÓUâ¹ù)¥9©Å½!»6	ıuÊ˜ô¯Û”÷S àÍƒ»!*òsR®ql‹™½,qİƒcLo›'Ïÿ½EêŒâÔäÒ¢TİÌ¼ÌİÄ¢äŒÌ’Ôä ˆ^n
ƒˆYjD”w’¥p–ıe÷tŸw7gš`jÓ+Î`ØŞk¨üÃùä
»3-{´]]Ã> Pœ^```

## File: ./.git/objects/26/c2a083deecdd9380c1bb8a1bbd1024ea8a6053
```
x+)JMU0¶´`040075U00ˆ/(JMËÉLÏ(Ñ+Î`ød6kæãŸÇ§ûŸ©ÿèşnÃÆ&¨RC ÒÄäìÄôÔbÊñìt5“_9­Ş®*<aRUUid_š’ZVvwÿ5ŠçÏtùKj§,–şæUelŸšW”Ÿ“RÇİ©|«—uI³ã­×15³5&BÕ™€ìÍ)r“““³ĞÔå*>SòÛH-Ñ¸ˆÅóT‘©A|rQeAIIbXå¯œz6…»›~yşè¬=0fœ™A|f^fIQbnØ?äşİîì:wÖôûç6Uçì¿a5ÔÜ >½¨là'Õ—óE¢7Ø/Ùİ¼¢ï±]ÏU¨*ƒøâÒ”|µ¡™«ßËş·âm0—Æ­Å“/?‡ªJZZœRd?WŞáÖ6M¯LCŞWÑ•Ÿ~ŠlÈ´  Ñº›”```

## File: ./.git/objects/36/b611530a7744e9b8c8a100715ffda2e95ad445
```
xÁK€ @×=…`cL<”‰|U¹½3¡ô°ûbé¥’ƒúêlK„‰!5:¾§È0¥®Ò€ÓqÉÒ]"ê)J€U_ıC?ÂÊå```

## File: ./.git/objects/38/2b3cb8d2004f2a1675b9aa621baa19e2816ebb
```
x+)JMU01`040031Q(HLÎNLOÕËÉ,.a0Û&ÌUîòrÇ‰……ñ½Œºâ
 sÍ$```

## File: ./.git/objects/3f/9d1f40dab6294a69310dea5b79f2f914b06938
```
x…TkOÛ0İçüŠCxõµ¡Iƒ”AË*Ñ…nÒÄĞä&µ–Ø‘íP*´ÿ¾k'…M#Ÿ"û>Î9÷øÎr5Cïı‡Ã7›ÊèÎLÈ—÷˜1361Ri•ó#dB
3o›9€=–/ØÒ ayÎSäÌXÌ–0<©4oQ ¥¸}J¾ªt©eGe™/Q0™2«4…V©Âœé”K!ïp€DI«•/§ùL)K'•´©ZÈvnÑâ•B)J1‘†-÷öÁ“¹¢„?ä¶ö¨:ÇîÁö ÛÓİ}ÜbëmxŒßT€-ŞÔn1’åÂ¸Îfi,/ „A°ùÿhõÚEãóh:‰¿ãúëù_¢ø¼?/°ùjşs,}™)x(N+
n,+ÊŸîOUö¤K¦Q|ÑŸ„n“ÓkÓN;»>êY|LGWƒáeÿ$ÜÚ+~¹rß‘Â•¦I&vÎ¡i¤×.<'=«ÜšvÆ)Â­¦/òtó"–qšèŒz!	C‹Zi 	\ñ"¼È4»+¸´X;Ç½ğh%Yˆµ%N×;Ì2 ãÁk×ãI|ä\]³”–=†{nÑLiKÛ¡OÑZÙZ5È„E/È„SfX£Y³ÎÓË‹æfÅ“iˆaàY4üÑ*pxØ]kæ~ıìÂà/«&×nî‘çjÍK­ŠÒ‚ßsz(ÎDäUW>÷,‘z×Æ`8.ÉŸ£QD>=@Üÿ<™Lq6†ñ(š'c§é«}Qû¹#Â]øaÀhXÚ¦JnLV‘–½³Zã·+MøÔ—–ëSX…³h|Ö¿¬mùòå‡MÒ„ ÂÔîmŞ¬—ŒU44fë±‘x~u‰^×­#%SCı5g)Z4ğ.Z;;x|2SÜôd2á~ıĞ"«×{¼QºÁj…ÔÑÎ4«v›‚È}Im‚VbóŒVüŠ`œ#```

## File: ./.git/objects/45/d78545c12e7c263e0be909a1d7a891b3fa28cd
```
x+)JMU°4e040031Qpöpôswõñw×ËMa˜9s/ì‹î<3qé–5·Õš¿ğ‚ª+NM.-JÕÍÌË,ÑM,JÎÈ,IM.Š€´‰˜¥FD‰q'Y
gÙ_vO÷yws¦	 âô#Â```

## File: ./.git/objects/46/1e1e1e38292d0a73cc74fb32266133720449fe
```
xeTQoÚ0Ş³Å5¥ºAZTí¡ˆiH©­ªu{¨B&¾«ÆmÔõ¿ïì@`]^"ÛwŸïûî;¯”YÁùàóàÃñQ\Ú"^I£ŞÀŠÛ5;†k#J…—pq¶ÌyÖ{·e‘K›ã<WÜ¯aÍZêHM÷åJ~Ç
~¦ÀK·FídÂ4š'Ú–Z ¸%åT}k@ZY†Br‡„ÈS‡E()‚sÅÏuø"­óŸJj´}Æ,:èai —9¦\*fyÕé¾&kC'ıÖshu]í'S8ùÙîÂZ§ÑŞ€WÍ/Î51Á?Ü"Æh½œ^Í&w£úbtIì…qb²ÌèçûşÈë2F‚,gW7“QÛ‡-ÓT&’ä9 K¥ÂQ ÷Z&&&!–XYHJl³o“›ûC ŸJY 8µÍ˜ïE
RCÔzm*Ÿ]¼_aB•2…ù —RPÁb1ß°pèQîe{=2iíN_ã%PR›j´.1l¤’…ÿ1üÀÌlÆ³Ù¾s»î×İg€oŒ ŒÉ×F¡¹¶,ñêIˆ¼Î;ÇÄ"
õî®¨MG^ÊÉ_^ÔÔÜÑ9×mıİ€Në#x kAïiJp»îÔĞïu8,å\Â»è Øè0‚Êöàíéùí„Bek¢Ã ¨¹¨šâ©m»”½”W5¡Æ÷púßÜœúş57ïeäÏĞÛ itH•¶<í5¦Š İĞiÁhä“à•*“Úë_H‚ÆG£ã©øo³İi×–úC>§6:¤	l¥}—å|‰nb]*Uw0Dd›}€7c]»JØ¾{ƒÓ;£”y®Ÿ_ŞV.&ŒÆÃQşg‚†4Wè0ú|‡```

## File: ./.git/objects/46/fa6ce82e3c0071bb8370fa49f810897dc09f31
```
xuTÛn1í³¿bâmU)ˆHQB¤¨¹T4ô…¢È»;€ÅÆŞ®m”¤ßŞ±—[¨ÊÓbÏÌ93çŒãLÇĞjØßk:S4c©š¨æ3eûp£S—á	>$Å"·VÄpñİ¹6ts®ÕXN\ĞD›4WQ0Ö\^]Üµ£X$3Lázğí8•édF…ï§ÒÀc¨ôe´+
Š`0¡j‘TÒz(fĞB„NC.s™1#µú`2Õtü—B¥–
‹Pı|p	÷Õ:Œ ò‰wà)ÄÔ‡'úñQ¨¢9ğJ‹Ãi3ÅyS¹,ƒöéÇ¼¾Â²&¿‘ÆH59Šë >K-*å«ypàÃ£Ãr‚¤°ÿ5¾l–³@âl&ÓòÓ"2šÁ™™3X„Y…ñ#™ äÂNY‚È9ğ²´`5µ³š{“Æí˜T|­Ÿ Ñ½ŸŒÉ1‡°QL}û"ş˜ÃhÔ;EÅ€~¡©^¿×§W1^¥-˜‹L’6^:()òVN†%cƒÁÕE·RMBdÀÿ‡HûTG­‹òzô?¨çÚei€›Ş!Û;h“·H2Üİôº<¸­ĞÚrv}uKÒ»•PDi…¹™ù2–©nG%ı®pV“0ûĞSÆ{wm[jÉXÃŒK5Xí’é{u}JóLJ!ÔëÊ‹ ¢õ®¸Ä]ä9’ß(|¢á•˜˜Cô¸*)ò÷dÆµ1wZ;n½áí9”ªîâiæîºïè„Ğ˜ü´8Tk•Cø®ş’RY×QølßZÕR¯PNw×|C–afp£ëYèŞÇ·_ÈÛvùŠ,äWxÅf#;ø[0Şm›%\Õ[ï­¤V~Ùó-¦’+v’¼å”B<}AFE±|œı¡–A```

## File: ./.git/objects/4b/825dc642cb6eb9a060e54bf8d69288fbee4904
```
x+)JMU0`  
,```

## File: ./.git/objects/55/6940abedce6bfea8ed6e130a3028daa393d3e7
```
x}“moÓ0…ùì_qæuZ;Ö¦HCìE!èĞ$ö¢®âK©&7¹Y¬%vd;…hÚÇvËZ† Ÿ¿œ{síE©8yûîÕîNÒX“,¤JH-±¶`»¸ÔYSÒ)‡w¶Éô NŞ4¦ÖÖÏ^×Nj%J„5Âd¤¤ºG×ÉŠ¬U}Fºq£aÏ«MiQEIø‘ÕI)Ã¢…¥´1Ô—J:_?¤+à
‚·"V)‡ÚhG©£lÀ˜%‡>5µ¬)²dV´İŞ#(-´_ÿ®fèt3áû¯÷Î±7İïaÎ?Ã“-øìx8ÿgÌÈĞ75øXåÚ[]qòNªÚ–dZÂè~ö6šÒÙøÿ’³6¹šŸ‚C(ËdÙ¼óèŸ8vFh0ŸŸfÅà¿¿ÛY×!Õòsñç´yÜoÈ5FaÈrÉØôãäËx:â	¹4	ÇÈØA–œc;ş0ç1wñÉ“úœU5rY<-–¢”>>ß`6½¼9¿ø:ñN·z»zœÅ ùÿ¨9Ş{ÈõY_'"ßÖºk"o¹÷±Å±ïKIûiÎCT;+ğÍì–èËÀÆ“Éõä4º„;âo®´ƒ¨ë²‰¦…P÷4X'X¡ŸoiÇXé§txC]Û¿P>¿²üİPæ¹0ş±píËÕ>ô+·tÃ0ö‡3ó²äÖµ¼OêïnGóÒ?Û¤)Y›7eÙò_y¯8ó```

## File: ./.git/objects/5e/4503e6924e3bf39bad9a8d8b26a1a8bf35aa17
```
x+)JMU°0f040031QH-.HÌ+Î×+Î`¸3ÿ]”¡Ğuû†-™÷æ,p™úÓJªª83=/1'>%µ8»$¿ ¤˜íËÚkoïHY2á‘ÁäÉGŞ°^1 }%œ```

## File: ./.git/objects/64/433ebcc2816b71f19ce90760c873e0f1915f5d
```
x•A
Â0E]ç³df’ÆDÜzŒéj 1Óû7Ğ¸û<xïk-%u +z‹H9¬3"²ŸteÏ3Š#Yt±Q-Í^lı]dmé÷…[>†W‘”/ZË}T½µ9
p&B4ƒ·ÿõÌó“z’GÀì]÷6‹```

## File: ./.git/objects/6c/176b67260cc928f5093aee31aa7111c8347a73
```
x…TíNÛ0İï<Å](+0…®hF5¤i…­¢TàÇT
râÛÖ"µ= LÚCìö`<É®“´M7¤åGäÄÇ÷ãÜsœæ*…öû½¯6^·¼5­TÈÊ;H™Fp¢¸ÏqÚïn4ËnÙín±qæV–vzÒ:–ç)ƒ°ÀÀXøæSqŒs8êuO÷à-œŸ¥wÿòøR¥œu†iJq1fE •UŞdÈ!ƒÅÌL„’Â½pSpSªO%g(h£fùnYt W …Æ1ydÙ|kû0›*ÚøJ¡±Å™Ch¾İ<‚Í‹æ6Œ ±wàG$y€gj6c’Crq£ÃA‹ã]KzêrïàM ŠŸk…œìá:€ÂA›B…h!9ÄÃö»Ñ‚#^1rEUüî…¡®½¹pmQXÏU¹bÚ%t|©‹*®!ÖÙ( ¡/É<À?×³Õì’9\E@ßW«\¤šÍ¿7®~Ø¹u8ãIfæÚÓ^WJ£´všd¹¹¢”ô,şZ4wh*è-¢fÖ>dBg<†úº†eŞ…Ñ+í„’,ï@SÁdÈâPf&ŸR90%Y \´±Öv­^]¦YÍâ¬”1T`R†‰ëÆÑË6X—?<ÿüµ8_“¼Q³å×n˜J Ÿ¬ñ¢˜gŒè4`3#4MõÿÒ%!--¸TltrÚ½ìŞt{ƒqãqõµŸ4¶ô=ßşGgÇ_ú½ó‹›£^ÿ@+LkáÖ¢XÒaAR_1„Z—×óÏßq$Æ0ÂkHÆäŠzĞF£N0¦$1ƒÓÁş"„-â£+O¾bÖĞ¹Ò:ÑXTe"u|:» ®¹ÈĞe¬M¼&ô"quÕê/MjH¡y=¼Ş5ÿià‰îÍÖõ•İi´xà~*r$­1ºèÛIÈ‹AÚe"ïÓn\nÕ]X“c\@–ªçJ’ô‹8µ©..Á…wãè@aÓ ```

## File: ./.git/objects/6c/56d00dbfb8ac21cfce308a4f192b64a31bf64c
```
xUSÛNÛ@í³¿bº	
7Ç†¶T¥RJB\9	Â­í!^áxİ]oªˆ ñ•ú…|Iw×!¡~òÎíÌœ9ç<†=ÿÓŞ‡ÆGOIáÅ¬ğ°˜ALeæ4à’§*Ço°ïß«gmk(Qr©­Çi… +Á’
nTÌÎq&„N“°XH%Ê\MŒyŠÓ…ÌX©‹2&aj@ÿI®D‚)Äs˜è,—¬2Ä
\TJVâe¹#é|së	0É¸ö ‰Š[hn¦¦ÖÎÆ	lŒZ[pÍmrÏs]®©`46é—/‚û“³‹ C<¬ÏôíÙ¾Û©wxèÎõ<8o[q®ƒ«^?ì=ÿ‹OÀ~ÕÌ3,R.à¬Â~o|<êÿ³ÿµkÀqFó‹	¾¾ü	Q–¼œœõúûĞÒ4KOJç@n÷ı;è–e>gÅd…±æ•˜‚šY%QöXñF²3\•Hs<B˜,Áı­(^."Š[°XÀ“cæ°˜İ45`¶œM„JÓ½\›­Hêh•r¦7.=]-ñË÷OÁÖÒ0ÂfÆRAïBÂ…@-˜š4¯ZIµ´HAÑ$A)áA³™¢|¬x	TUÙ–cWMÎƒğ*¸èt"RWÛÈ.Ç?†7ÃQp¹¶sw4
‡O,½¶Ëy6Îf½Å÷ŞA_»—Û3şË~/ĞşÁo§a<Ğï7µiÔ=İÑ–eË!i† CjU6W#ğİ3ú*T›í…˜sªÇ]İŠc³Ì›¦SMQQ	k
èZş£¯n2Añ^3ãU90åõ1½¾üS>CK¯@¦¥'ÖÇZeXX4V(lçĞON```

## File: ./.git/objects/6e/8bf73aa550d4c57f6f35830f1bcdc7a4a62f38
```
xKÊÉOR0c0Ğ3Ô3à >í```

## File: ./.git/objects/82/c146789513a554fc4e366b095143d409b56043
```
xKÊÉOR047dğÈ/.QÈ())(¶Ò×OÏ,É(MÒKÎÏåR Ç”ïÔÊâ|ÇôÔ¼…ÊÔb°°g
—Y’™ZìŸ—S‰.\é–™“ªP§¯W\œ¡Ÿ™_Yš”i_œ¬›#˜š€Ò¤ìÔJÇÒ’5É‰%™ùy`K ÜÁ<G```

## File: ./.git/objects/8d/54bab212fd426892fe8b350df6025111d9c1bb
```
x+)JMU0¶´`040031Q00ˆ/(JMËÉLÏ(Ñ+Î`ød6kæãŸÇ§ûŸ©ÿèşnÃÆ&¨RC ÒÄäìÄôÔbÊñìt5“_9­Ş®*<aRUUid_š’ZVvwÿ5ŠçÏtùKj§,–şæUelŸšW”Ÿ“RÇİ©|«—uI³ã­×15³5&BÕ™€ìÍ)r“““³ĞÔå*>SòÛH-Ñ¸ˆÅóT‘©A|rQeAIIbXå¯œz6…»›~yşè¬=0fœ™A|f^fIQbnØ?äşİîì:wÖôûç6Uçì¿a5ÔÜ >½¨là'Õ—óE¢7Ø/Ùİ¼¢ï±]ÏU¨*ƒøâÒ”|µ¡™«ßËş·âm0—Æ­Å“/?‡ªJZZœRd?WŞáÖ6M¯LCŞWÑ•Ÿ~ŠlÈ´  ¸ñ›v```

## File: ./.git/objects/8e/b8897edbb4411716da38f03ca59ac0f2c38724
```
x+)JMU027c040031QĞKÏ,ÉLÏË/JeXÍûÑ¼ë¯ËógÔL#ïj2…ñÂT•¥gæç1äu·Zpåh}¾i3¿ôÙãK–é[˜ BbJJ~^1Cœ+ó³I~ÖŸg¯ÕÛ­¶pÅ~ÓUâ)ùÉÅ®×[]êÕ¨Ùq¿ä\x}ÅÄÍ¿4ÎB¤s2‹KŠ,´mv\bğ×+İ¹*Iz•ä£Æ¼İùÜü”ÒœÔbµCšï½¹;¹áàî.é½*¯º‚!*òsR®ql‹™½,qİƒcLo›'Ïÿ½EèsSS…âÔäÒ¢TİÌ¼Ì½â†İá½†Ê?œO®°;“Ñ²GûĞÕ5ì=r¥```

## File: ./.git/objects/98/cf770a2cdc4418c35005d801ef2224b047c144
```
x•KN1CYçµG Tç?Bˆ-Ç¨TW "™Œ2iq}Zš°³­gË<z¯6çÖ(9ÆdÏÙZÄ€~'‹6L.ë²±‰a³êFS®¼µÆHfŞ"ú°`bI:xÍ1Ñ§GWÜ®èXßcBãYï7xkaÓÇW§Ú^yôwÀàqÑ9ÏˆZ«3=ß-ùoO}^ëªÔà1pr´}ìG£	wácÊK=(“ºüù£ş ^uR<```

## File: ./.git/objects/99/99bd0c1de88b6e08cc5e6739fd29b67d37e84a
```
x-ÁNÄ0D9÷+,õ²ˆvå¶ì.â†8qà"7qÛhÓdå:,ü=)âdÍŒíC¡¿t5¼/gi®ªº<vG„Cı©Å¡ğ±já#zõ`M.˜„V¾'¹–ìs÷x{Ds‚Ÿm +Šì•fŞèÑdÇ_h8J
<ïùÚÀ	•Ÿ›*œÑ8!›A3K.ŞšÉG¿-¨”s–ü/‡à7»xe«Y'ÊAá	òÆR«ĞŞãÍ¹‚ºdóÊQI}Š@ÑäSH÷ªúçYÚ```

## File: ./.git/objects/ab/0df1378afd44dccf89cc263559dd2902560e51
```
xKÊÉOR04bĞ+.ÎĞçÒÒ+./à <¥”```

## File: ./.git/objects/b0/7971e58a7e365e161bfa065132d16c3cffe61b
```
xKÊÉOR0402aH2ÈKÌËW°Ğ3c@/­r’‹ŠPD±sR’Ê³±K¡ˆ$&g'¦§ëåd— ÈŒrFC`4è¡èv  |```

## File: ./.git/objects/bb/578d3123f843c9a83ecc6884bc2bc2d5ac0791
```
x¥TÛnÛFì3¿bÂ(–”€¦ EGFÛXnÚP!5…*+òP\˜ÜewIÙJ Oı€¢_˜/éÙ%-+Ñ>T€%ƒ<×93³*ô
£¯¾üú‹ÇâÆšx%ULjƒ•°yğ–’ÆP$•¬m¿ÿ…RHm’œlmD­2ş+uÚÂà—f%¤m|v~:}\˜””TkdF”t­Í5
Âb«¥M)
4–Ì1DQ 2r#ZS
]7ZYè„ç€TV¦Ôö"‹°Mª¹fô¿>A`©FDF%+Ê„,‚¶(æT7
½^»5Ri(á·®ağİ·óÉÛÓóÙ8ì’üÍï/Êÿ…Ã¨®Óa\L¿ï˜^Nâ=XÃ ¼â,D'ua>şìübÂ…»Gû)‡<MtC	Np2¨‰‰6İe…C<?9ñRb;¾ÀJrÍ"üU-ÀsŠšĞöäO~î±Dïi|‚ÉlöP?ÎÚ _ìFÖ¹xî€p^S;töÖú„!awé8ÂwÛø½;cO ²¼WüO†²B®óV0ı¶`Æ%WÖ¿X rx–å··àyvãû~(¥µ<è!wItY
•"Úxá$Ni«†)xWÀqÒÂĞoß=å4ÿˆSîBŞ0o]ˆÒ5³ÓW"Ãt5mQ÷Xl˜MbUëÚív*m¢7œÚÍè—ºœ¾¹˜ÌÇƒ¡SMIF&»ˆL[×9kçgó1O%xz&NŠ~Ù1Rí/İ•y6„½,©V„Wx5È$¯ûfQ)nRªê#Dõ¶"dˆ<û‹£èÅÒ½}ÊĞgš©ê#ÜÂjÃ’yç‡åÒÒæÎ!Dq-¶YÃ¢-O,3¸ketwi!ßíuNê³şyâ½¤aÉ‚÷Ôje÷às8…4Î@ø )™—aà­Ê½
{ï; ß,?„;ô¼NBàã²LØ©ÓsÉzöXî8¹©Vd¶Li´*IÕ÷vÈTw.Am\'dğ¯)îÛ«ç¦½·7o³<¶/²óXú·é½Ù^½å¶Üb}²†× ÛÅ	™>§¢ğÊb™XGÓñüõèèÅ‘oÙ¢çfm­6É7y­Ëª šqş6~İ‘öíåçóY\±ûò```

## File: ./.git/objects/d5/5c9fee5a3112d73f80b469de9ca04495f93a21
```
x}Á‚0†=ï)špÑ¢ñàcèÖÀ’±áZDŞŞ‘0½yiÓ?ßÿ·m]há\×‡¢D&¾iM<¡çP…Øk:Ö=IÉ‚QÈh¥–4Bf{+ÃÜV]³íÛ#9B&Ö…XRÔâ]@“ÒPkÑ—ï¦)q4×K•Å³	€“€õi¥sPıç¸SoY(Â~7 ¯I0Å—í‘³d x·¦ÒÑIeG†â¥Tíáœù#7U} !sm¿```

## File: ./.git/objects/d6/0ac9865c9ba661aee0c602ed8371939ffbb421
```
x+)JMU0¶`040031Q°0ˆ/.MÉ×+Î`ÍtXıö\ö¿oó„¹4n-|ù9 \Ñ%```

## File: ./.git/objects/db/ad64acc00d43669a540e1e6132e7773240ec45
```
x=Œ[
Â0 ıÎ)ö_*»y4)ˆx¯n·!’>hƒàí­ş35& gNKÿ®Ğ½Ç¨y`k)°qˆnH2j­mÖ3Y«ê{àešrUõx¼ğBMw)y–¯I²Aá-ï+\ËlwOSÌårt7 ßãBKg"D¥›4UöšçÿÕ<û1```

## File: ./.git/objects/f2/255c44e89f145b71b03fa4bb83a88ee33e8cd5
```
x…VÿnÛ6ŞßzŠ›âÎvIIÖ"€İtH;)Ö4“n’Ì ¥³MX"U’²ç%ö{Â=É”e;µ±†!‰äıø¾ûî8Hå ß~·ó}Th¸ˆPLaÀôØÛK™)¶àh¿?RÅ t¯•KM_/˜JPÀyïË)Ì¸]ä¨

v!gZÏ¤J€‰®Ù EPË)ª9d(
@aGMnÇ\CæÜ=iY¨ÌAc\(¸à†ü;cªı@H•±œÇıÓÉ"‘À…A%XšÎ›¡çi4`!!ç9O=Íææ#`<–´ş½¸ƒZ#a¡¾ûª¯nëMx€Úk¿Ï@LìöXf™Í%˜‚_;ğá}”à4EšÂáûàé	6ıK®5£Ğ¾6àÜÀ™²Ö¬sğïöJäÆEÚ\¥¯S†Ş}Ïy‹|MœI&Éğ°\)rr`7,Ì:g<M[>” ¸! XémE‘P¯}¹éôêyaşêäÙ·´-ƒ†e½öñæäôS§ßë|¸ú¥ÓûíøŞ7ªÀ{¿¹f£‡_®ÌË*?0”
X2eÂR-©r˜á’¨m`ÂÍá-´LqĞÄ!Yô2B_åà_++eä® —0şwóèóC|ªíÅLÁµGzŞÛ{ö©4<€ùÓuZĞnĞûë&¬X¹™ğ<·|¼´[ñ¸O‡<Ô,ö¨lƒ €SOŠ"Š’
bÈŠÔD–»èñ!ÜİA0Ü²üğĞ¶˜Øx\ÑÆ9ÛÌl×%1`k`YS6fk@Dùÿó½!¯2ëMÒs8lRí˜ö«$G
)ü¯Pÿ}kaÔ7“f–úy	„¦øum7¾¶:9.CŠ¶8ó0ÕH89Å×ÿëtJ:"lKÜ«°× :GaËwQá×§?ŸuaL]Ôt{yİ¿8¹¹èw?~êû‘ÉrW"a%…°V£ú^±Ø+„°%¸MûĞ˜Ë‚*ŸÚÎ ©Zº­’6õef<FÎ¢½VmÓnäb*'Öƒmm…É#I”ª„Á,‡!§mMçLÙvæmç‰6[‰½H’²±	×l6ú"[×»"xÌuh¨}î>×7Ú6j›HÓS™Î¦á…¦ş´²¶NZéz]MK1tz½«^ºÔó	$JÌ&‚Õ°l¤£NÒõÜĞ·EâÚµ#wÅÈ¹4UCĞcêëÖ1%Y¶€_'ê¶,Da½ÙïÇ…62£.¦hè™tî*aV+4çhb‘ˆÔ±â¹!
™.-Fv!>”¦M3	)nl2’§³°çèWHëö›k]Ô?‡|ÒlEÊ	c0„ƒ;J>pJ­œÈ¦5g€2*
×¨¹-ÂÊ)ªŠ®¡ã’UİöKëvÊÚÁk+a;+ÕÀ»w«®G7{Û +Å*¶@Àîp_Ûw3{9«ô±ï&•ï}ãÜç’Ï-£ˆÇt“€£·o·ÇR±ÖÃÑÕ–x9šV¼WJ\›µN!yNŒÆc&F¨iØÙä×¶¬kÙq±Oö‘§h0„f˜è®dìå§Jşùëo ûBÌ„ š#‰/îL˜Puş¥ Û```

## File: ./.git/objects/f2/369abf69bc33f9c797134fcc7ff147eeb0b182
```
xmTíNÛ@ìo?Åb¢(A8´U%P¢V%Thh HUUöyŸr¾3÷ˆ ©Ñ'ì“tÏIH"ÕlİÍÍÎÎ/*îÑ‡Î›ı½¶3ºpÙF9‡$6y°Î¯Rc&ø4·-“Ãßßü
.Xlf ÁLií¤är
™ÓqÉ-*uİæÜ@Æ½¹´(-W2b¦ ×!«9³‡Ë”8D1%mLuÒ¿°`råDJåÀ(§¦ 4à#•³ôqml+ZˆĞ)(y‰YÌ-Å‹Fó	åŠ¶ _¨„'ğwEpc±„î1ÌQóŒ4¹TÁƒÒÔ^C*¥Hò³|MÏá]¬öØ˜14¦Õj…Ï`oIÍOÀæ( §:5†£ãå®Tâ9)Œ²…z‘$:6†Ê¦dš“Ãà¤PlB¿~Tñà#Û2¾#ıèx9?ÎÀY.¸åd}Uö³Ÿ”×ªñŞqMv1UäôRñhğ½×&3ˆfä~
©rŠó8-šÍMÂÚaÇ'/ä]ª*=U»+:ˆæ„a$¶MgÛÒ	GızwË†W+®¸1$éj¬ŠU)‚EUŒ¥<¬SåCÀ¥#àÆO±rÁ’şU5ªf/Jevìy»¶Ç·òÓ%ü+.€’mP2„FÎS?¬&{ŠiÒäÖr¨NÓ­†{~qzÓkTİ-wš~àã1Ôöı¦7‡Rv˜L¶úŞÿ7Ûë)'Ó\HƒÚ¾Êô?„F«­ÿÁ»u—¥pSR	j“ó2˜jåJÏ0Õ”ôèşÖ zÎ?İüº¾üqv:¸ëuáùyg¡SıA®ñRòzëd¸ãø{Ò¢$ı•5z;SJ³J/‚ËáÙh8¼í…µóáÕ ½ue„A1#D%i=şËÅå€ğ«¥öæV"ö0ğ× ô¡ßğ¹­P6«ô­ô_¯/2~J›Å0øD“r```

## File: ./.git/objects/f8/c46dfdb743459d9a97df68cf40b27b6cbfd83c
```
x­TÛN1í³¿bº„Š–©m‚š
Šú (òÚ³Äbco}	]R?¢_Ø/éx-HU+VZÉò\|æÌ™ÉK“ÃúæÆÖ‹…—Yp6Ë•ÎPO çnÄàĞÈPb6×†J+où¸p«åS°•qd:Â<¨RÂ½D‰\—5\)?‚÷ın¶ßï6À…ª2Ö/<Z¶®¼ç9ˆ×èsè!Å` R\•ÌñziùPŒY 9Ó§ĞZ’Ü#´W÷añs{Î¡õ:Ù†[JÀkHN7×Îá¤"'¥/€zLÂ¨È.zÇPğ±*k¶
z‘—Z¤ZÂÍxõ»Ãƒş‡Şğ`ğ¥w´›´–lIëzfè¤­~÷6èíÓ•Œ¶sŞçÒ\5çå¤Ió8C'ı{$ÁMŸå£DëËğFJĞ(Ğ9nk89~›Q¿@Z5Aë 0[jenŒ§úösÊTEµoü¤å"x˜¸9ç©7¦tÏ‡˜©„¹–Neóâ^&q’éP–°±÷j}ü5‹P=ÀŸlºŒ~~ÿAçe%¶$r—Lƒ‚40¾”ÊBZMu0}hU]¬JÖx-À;cmTqD|D±uàã \Å‰Í˜_I„•]øŒ'uG<VÚ\ÊáŒà•İ‚ËGJıÃÔh•€o#¡†•PÓÃHHÀ»›æo’6œ5Icâš-BíŸ œmm¥”½s²ÃÒá´ä87ğgßàÿ	»_Sd™$vo°ß~„ûé¸ŒĞ§uÈÕ%ÖªX€¾e ®cW¢„ïå«ôL½Á‘šccØá {rĞ;Şça`¬Pq<ËH¥”hƒfJø@ÚªÁÎ6#	rNîó=6“÷lÿş¾í´¹¢Õö¯óE4›ª´x xâJÅô¾E††»ùÒ›¦¾qV«’¦.a¿ àëç2```

## File: ./.git/refs/heads/main
```
98cf770a2cdc4418c35005d801ef2224b047c144
```

## File: ./.git/refs/remotes/origin/main
```
98cf770a2cdc4418c35005d801ef2224b047c144
```

## File: ./.git/refs/tags/v0.1-baseline
```
dbad64acc00d43669a540e1e6132e7773240ec45
```

## File: ./lists/package.list
```
ufw
libpam-u2f
systemd-cryptsetup
openssh-client
keepassxc
debsums
clamav
```

## File: ./modules/00_preflight.sh
```
#!/usr/bin/env bash
# 00_preflight.sh â€” baseline checks before running secure-init modules
# This file is intentionally small, strict, and self-contained.
# It should be sourced or executed first.

set -euo pipefail

say(){ echo -e "[PRE] $*"; }

# --- Step 1: verify sudo works (non-destructive)
say "Verifying sudo access..."
if ! sudo -v; then
    say "ERROR: sudo not available or no passwordless cache unlock" >&2
    exit 1
fi

# --- Step 2: check basic utilities
say "Checking required commands..."
REQ=(lsblk awk sed tee udevadm)
for c in "${REQ[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then
        say "Missing: $c â€” please install before continuing" >&2
        exit 1
    fi
    say "ok: $c"
pos

# --- Step 3: check for YubiKey presence (hidraw)
say "Detecting hidraw devices..."
HIDS=(/dev/hidraw*)
if [[ ${#HIDS[@]} -eq 0 ]]; then
    say "ERROR: No /dev/hidraw* devices found. Insert YubiKey and retry." >&2
    exit 1
fi

# --- Step 4: check plugdev membership
groups | grep -qw plugdev && HAS_PLUGDEV=1 || HAS_PLUGDEV=0

say "plugdev membership: $HAS_PLUGDEV"

# --- Step 5: confirm logging directory
LOGROOT="$HOME/secure-init"
mkdir -p "$LOGROOT"
LOGFILE="$LOGROOT/preflight.log"
exec > >(tee "$LOGFILE") 2>&1

say "Preflight complete"
```

## File: ./modules/10_packages.sh
```
#!/usr/bin/env bash
# Module: 10_packages.sh
# Purpose: Install core packages for YubiKey FIDO2 + SSH + LUKS bootstrap
# This module is sourced by secure-init.sh with the environment protected.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[10] Installing baseline packages"

# Required utilities
need sudo
need apt-get

# Update package lists
sudo apt-get update -y

# Core packages
sudo apt-get install -y \
    ufw \
    libpam-u2f \
    systemd-cryptsetup \
    openssh-client \
#    openssh-server \
    keepassxc || true

# Dracut is optional; Debian-based systems may not require it
#sudo apt-get install -y dracut || true

say "[10] Package installation complete"
#!/usr/bin/env bash
# 10_packages.sh â€” install packages from packages.list
# Called by secure-init.sh master script

set -euo pipefail
say(){ echo -e "[10_packages] $*"; }

MODULE_DIR="${MODULE_DIR:-$(pwd)}"
PKGLIST_FILE="$MODULE_DIR/packages.list"

say "Loading package listâ€¦"
if [[ ! -f "$PKGLIST_FILE" ]]; then
  say "ERROR: packages.list not found at $PKGLIST_FILE"
  exit 1
fi

say "Updating APT indicesâ€¦"
sudo apt-get update -y

say "Installing packagesâ€¦"
grep -E '^[^#]' "$PKGLIST_FILE" | sed '/^\s*$/d' | while read -r pkg; do
    say "Installing: $pkg"
    sudo apt-get install -y "$pkg" || true
done

say "10_packages module complete."
```

## File: ./modules/20_udev.sh
```
#!/usr/bin/env bash
# Module: 20_udev.sh
# Purpose: Create strict YubiKey udev rules + ensure plugdev membership
# This module is sourced by secure-init.sh

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

# --- Variables ---
RULE_FILE="/etc/udev/rules.d/99-yubikey.rules"
VENDOR="1050"      # YubiKey vendor ID\PRODUCT="0407"     # Challengeâ€‘Response / FIDO2 capable key

say "[20] Applying YubiKey udev rules"

# Ensure user is in plugdev
groups "$USER" | grep -q '\bplugdev\b' || {
    say "Adding user $USER to plugdev group";
    sudo usermod -aG plugdev "$USER";
}

# Write strict rule (hidraw, correct vendor/product, and uaccess for desktop auth)
echo "KERNEL==\"hidraw*\", SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR\", ATTRS{idProduct}==\"$PRODUCT\", MODE=\"0660\", GROUP=\"plugdev\", TAG+=\"uaccess\"" \
  | sudo tee "$RULE_FILE" >/dev/null

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

say "[20] Udev rules loaded â€” remove and reinsert YubiKey then continue."
```

## File: ./modules/30_enroll.sh
```
#!/usr/bin/env bash
# Module: 30_enroll.sh
# Purpose: Unified enrollment of YubiKeys for PAM U2F, SSH resident keys, and LUKS
# This module is sourced by secure-init.sh

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[30] Unified YubiKey enrollment starting"

# --- Requirements ---
need pamu2fcfg
need ssh-keygen
need systemd-cryptenroll

# --- Ask user for LUKS device ---
read -rp "Enter LUKS device to enroll (e.g., /dev/sda3): " LUKS_DEV

# Validate device exists
[[ -b "$LUKS_DEV" ]] || { echo "Device not found: $LUKS_DEV"; exit 1; }

# Ensure config directories exist
mkdir -p "$HOME/.config/Yubico" "$HOME/.ssh"
chmod 700 "$HOME/.config/Yubico" "$HOME/.ssh"

# --- FIRST KEY ---
say "Insert FIRST YubiKey and press <Enter>."
read -r

# PAM enrollment
echo "Generating first pamu2fcfg entry..."
sg plugdev -c "pamu2fcfg > '$HOME/.config/Yubico/u2f_keys'"
chmod 600 "$HOME/.config/Yubico/u2f_keys"

# SSH resident key pull
ssh-keygen -K || true
FIRST_PUB="$(ls -1t "$HOME/.ssh"/id_ed25519_sk.pub "$HOME/.ssh"/id_ecdsa_sk.pub 2>/dev/null | head -n1 || true)"
if [[ -n "${FIRST_PUB:-}" ]]; then
    base="${FIRST_PUB%.pub}"
    cp -p "$base" "$HOME/.ssh/id_yubi1_sk" 2>/dev/null || true
    cp -p "$FIRST_PUB" "$HOME/.ssh/id_yubi1_sk.pub" 2>/dev/null || true
    echo "Added FIRST resident key: $FIRST_PUB"
fi

# LUKS token enrollment
say "Enrolling FIRST YubiKey into LUKS..."
sudo systemd-cryptenroll "$LUKS_DEV" --fido2-device=auto

# --- SECOND KEY ---
say "Insert SECOND YubiKey and press <Enter>."
read -r

echo "Appending second pamu2fcfg entry..."
sg plugdev -c "pamu2fcfg >> '$HOME/.config/Yubico/u2f_keys'"
chmod 600 "$HOME/.config/Yubico/u2f_keys"

ssh-keygen -K || true
SECOND_PUB="$(ls -1t "$HOME/.ssh"/id_ed25519_sk.pub "$HOME/.ssh"/id_ecdsa_sk.pub 2>/dev/null | head -n1 || true)"
if [[ -n "${SECOND_PUB:-}" ]]; then
    base2="${SECOND_PUB%.pub}"
    if [[ "$base2" != "$base" ]]; then
        cp -p "$base2" "$HOME/.ssh/id_yubi2_sk" 2>/dev/null || true
        cp -p "$SECOND_PUB" "$HOME/.ssh/id_yubi2_sk.pub" 2>/dev/null || true
        echo "Added SECOND resident key: $SECOND_PUB"
    fi
fi

# Copy PAM file into place
sudo install -D -o "$USER" -g plugdev -m 600 "$HOME/.config/Yubico/u2f_keys" /etc/Yubico/u2f_keys

say "[30] Enrollment complete."
```

## File: ./modules/40_pam.sh
```
#!/usr/bin/env bash
# Module: 40_pam.sh
# Purpose: Apply PAM hardening for YubiKey U2F authentication
# Ensures pam_deny.so is immediately after pam_u2f.so, replacing any existing deny lines.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[40] Applying PAM hardening"

PAM_FILES=(
    /etc/pam.d/common-auth
    /etc/pam.d/other
)

U2F_LINE='auth sufficient pam_u2f.so authfile=/etc/Yubico/u2f_keys cue'
DENY_LINE='auth required pam_deny.so'

for f in "${PAM_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        say "Skipping missing PAM file: $f"
        continue
    fi

    # Remove ALL existing pam_deny lines to avoid loopholes
    sudo sed -i "/pam_deny.so/d" "$f"

    # Ensure U2F is present (insert at top if missing)
    if ! grep -qF "$U2F_LINE" "$f"; then
        sudo sed -i "1i $U2F_LINE" "$f"
        say "  Added U2F line to $f"
    else
        say "  U2F already present in $f"
    fi

    # Insert deny line *immediately after* the U2F line
    sudo awk -v u2f="$U2F_LINE" -v deny="$DENY_LINE" '
        $0 == u2f { print; print deny; next }
        { print }
    ' "$f" | sudo tee "$f.tmp" >/dev/null

    sudo mv "$f.tmp" "$f"
    say "  Ensured pam_deny follows pam_u2f in $f"

done

say "[40] PAM hardening complete"```

## File: ./modules/50_crypttab.sh
```
#!/usr/bin/env bash
# Module: 50_crypttab.sh
# Purpose: Configure /etc/crypttab for FIDO2-backed LUKS unlock
# This module is sourced by secure-init.sh

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[50] Updating /etc/crypttab for FIDO2 unlock"

need blkid
need tee

# Ask user for LUKS device path
read -rp "Enter LUKS device to configure (e.g., /dev/sda3): " LUKS_DEV

if [[ ! -b "$LUKS_DEV" ]]; then
    say "ERROR: $LUKS_DEV is not a valid block device"
    exit 1
fi

UUID=$(blkid -s UUID -o value "$LUKS_DEV") || {
    say "ERROR: Could not get UUID for $LUKS_DEV"
    exit 1
}

NAME="cryptroot"
LINE="$NAME UUID=$UUID none luks,fido2-device=auto"

# Ensure crypttab exists
sudo touch /etc/crypttab

# Replace existing entry for this UUID or append a new one
if grep -q "UUID=$UUID" /etc/crypttab 2>/dev/null; then
    say "Updating existing crypttab entry"
    sudo awk -v u="UUID=$UUID" -v rep="$LINE" '($0 ~ u){print rep;next}1' /etc/crypttab | sudo tee /etc/crypttab >/dev/null
else
    say "Appending new entry to crypttab"
    echo "$LINE" | sudo tee -a /etc/crypttab >/dev/null
fi

say "[50] crypttab configuration completed. Rebuild initramfs in later module."
```

## File: ./modules/60_initramfs.sh
```
#!/usr/bin/env bash
# Module: 60_initramfs.sh
# Purpose: Rebuild initramfs cleanly with HID/FIDO2 support after crypttab changes

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[60] Updating initramfs with HID/FIDO2 support"

# Detect OS family
. /etc/os-release || true
ID_LIKE_LOWER="$(echo "${ID_LIKE:-$ID}" | tr '[:upper:]' '[:lower:]')"
ID_LOWER="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"

# ----------------------------------------------------------------------
# 1) Add necessary USB/HID drivers for early boot
#    Format is different for dracut vs initramfs-tools
# ----------------------------------------------------------------------

if command -v dracut >/dev/null 2>&1; then
    say "  dracut detected â€” installing HID rules"
    sudo mkdir -p /etc/dracut.conf.d

    # Correct formatting: NO spaces inside += quotes
    echo 'add_drivers+=" usbhid hid_generic xhci_pci xhci_hcd ehci_pci ehci_hcd "' \
        | sudo tee /etc/dracut.conf.d/99-hid.conf >/dev/null

else
    say "  initramfs-tools detected â€” installing HID rules"
    sudo mkdir -p /etc/initramfs-tools/conf.d

    cat <<'EOF' | sudo tee /etc/initramfs-tools/conf.d/hid-yubikey.conf >/dev/null
# Include HID + USB drivers in early userspace
MODULES=most
EOF

fi

# ----------------------------------------------------------------------
# 2) Actually rebuild the initramfs
# ----------------------------------------------------------------------
say "  Rebuilding initramfs now"

if command -v dracut >/dev/null 2>&1; then
    sudo dracut -f
else
    sudo update-initramfs -u
fi

say "[60] initramfs update complete"
```

## File: ./modules/70_grub.sh
```
#!/usr/bin/env bash
# Module: 70_grub.sh
# Purpose: Harden GRUB with a superuser + password and disable recovery menu entries
# This module is sourced by secure-init.sh and runs as a normal user (uses sudo internally).

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[70] GRUB hardening module starting"

need grub-mkpasswd-pbkdf2
need update-grub

say "This will:" 
say "  - Set a GRUB superuser to '$USER' with a password"
say "  - Disable recovery entries (GRUB_DISABLE_RECOVERY=\"true\")"
say "  - Require the GRUB password for advanced operations (edit, console, etc.)"

read -rp "Proceed with GRUB hardening? [y/N]: " ans
case "${ans,,}" in
  y|yes) : ;;  
  *) say "[70] Skipping GRUB hardening"; exit 0 ;;
esac

# --- Backup /etc/default/grub ---
if [[ -f /etc/default/grub ]]; then
  sudo cp -p /etc/default/grub /etc/default/grub.secure-init.bak
  say "[70] Backed up /etc/default/grub to /etc/default/grub.secure-init.bak"
fi

# --- Ensure GRUB_DISABLE_RECOVERY="true" ---
if grep -q '^GRUB_DISABLE_RECOVERY' /etc/default/grub 2>/dev/null; then
  sudo sed -i 's/^GRUB_DISABLE_RECOVERY.*/GRUB_DISABLE_RECOVERY="true"/' /etc/default/grub
else
  echo 'GRUB_DISABLE_RECOVERY="true"' | sudo tee -a /etc/default/grub >/dev/null
fi

# --- Generate GRUB PBKDF2 hash ---
TMP_HASH_FILE="/tmp/grub.password.$$"

say "[70] Running grub-mkpasswd-pbkdf2 (you will be asked for the GRUB password twice)"
# This runs as the invoking user; output goes to a temp file for parsing
grub-mkpasswd-pbkdf2 | tee "$TMP_HASH_FILE"

HASH=$(awk '/grub.pbkdf2/ {print $NF}' "$TMP_HASH_FILE" || true)
rm -f "$TMP_HASH_FILE"

if [[ -z "${HASH:-}" ]]; then
  say "[70] ERROR: Failed to parse grub.pbkdf2 hash. Aborting."
  exit 1
fi

say "[70] Got GRUB hash: $HASH"

# --- Write /etc/grub.d/40_custom correctly ---
# 40_custom is a shell script that prints GRUB commands; the first two lines
# are shell, the rest are GRUB config. The exec tail line prevents the shell
# from trying to execute GRUB commands like 'password_pbkdf2'.

sudo tee /etc/grub.d/40_custom >/dev/null <<EOF
#!/bin/sh
exec tail -n +3 \$0
set superusers="$USER"
password_pbkdf2 $USER $HASH
EOF

sudo chmod 755 /etc/grub.d/40_custom

# --- Regenerate GRUB config ---
say "[70] Running update-grub to apply changes"
sudo update-grub

say "[70] GRUB hardening complete. Remember this password â€” it cannot be recovered."
```

## File: ./modules/80_sudo.sh
```
#!/usr/bin/env bash
# Module: 80_sudo.sh
# Purpose: Optional sudo hardening (timestamp_timeout=0)
# This module is sourced by secure-init.sh with the environment protected.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[80] Optional sudo hardening"

read -rp "Enforce sudo reprompt every time? (Defaults timestamp_timeout=0) [y/N]: " ans
if [[ "${ans,,}" != y* ]]; then
    say "[80] Skipping sudo reprompt hardening"
    return 0
fi

TARGET="/etc/sudoers.d/90_timestamp_timeout"

# Create temp file for validation
TMPFILE="$(mktemp)"
echo "Defaults timestamp_timeout=0" > "$TMPFILE"

say "  Validating sudoers fragment with visudo -cf"
if ! sudo visudo -cf "$TMPFILE"; then
    say "ERROR: sudoers validation failed. Not applying change."
    rm -f "$TMPFILE"
    exit 1
fi

say "  Installing sudoers hardening rule"
sudo install -m 440 "$TMPFILE" "$TARGET"
rm -f "$TMPFILE"

say "[80] Sudo reprompt hardening applied successfully"```

## File: ./modules/finish.sh
```
#!/usr/bin/env bash
# Module: finish.sh   (always called last by secure-init.sh)
# Purpose: Apply mandatory sudo hardening + controlled reboot countdown.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[finish] Finalising system hardening"

###############################
# 1. MANDATORY SUDO HARDENING #
###############################
say "[finish] Enforcing sudo timestamp_timeout=0"

TARGET="/etc/sudoers.d/90_timestamp_timeout"
TMPFILE="$(mktemp)"

# Produce the rule
echo "Defaults timestamp_timeout=0" > "$TMPFILE"

# Validate safely before installing
say "  Validating sudoers fragment with visudo -cf"
if ! sudo visudo -cf "$TMPFILE"; then
    say "ERROR: sudoers syntax invalid! Aborting."
    rm -f "$TMPFILE"
    exit 1
fi

# Install atomically
say "  Installing sudoers hardening rule"
sudo install -m 440 "$TMPFILE" "$TARGET"
rm -f "$TMPFILE"

say "  Sudo will now reprompt every time."


#############################################
# 2. FINAL SUMMARY + REBOOT CONFIRMATION    #
#############################################
say "[finish] All modules executed successfully."

echo
echo "Press <Enter> to CANCEL the reboot countdown."
echo "Otherwise the system will automatically reboot in 10 seconds."
read -t 10 -r && {
    say "Reboot cancelled by user."
    exit 0
}

say "Rebooting now..."
sync
sudo systemctl reboot -f
```

## File: ./old/80_sudo.sh
```
#!/usr/bin/env bash
# Module: 80_sudo.sh
# Purpose: Optional sudo hardening (timestamp_timeout=0)
# This module is sourced by secure-init.sh with the environment protected.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[80] Optional sudo hardening"

read -rp "Enforce sudo reprompt every time? (Defaults timestamp_timeout=0) [y/N]: " ans
if [[ "${ans,,}" != y* ]]; then
    say "[80] Skipping sudo reprompt hardening"
    return 0
fi

TARGET="/etc/sudoers.d/90_timestamp_timeout"

# Create temp file for validation
TMPFILE="$(mktemp)"
echo "Defaults timestamp_timeout=0" > "$TMPFILE"

say "  Validating sudoers fragment with visudo -cf"
if ! sudo visudo -cf "$TMPFILE"; then
    say "ERROR: sudoers validation failed. Not applying change."
    rm -f "$TMPFILE"
    exit 1
fi

say "  Installing sudoers hardening rule"
sudo install -m 440 "$TMPFILE" "$TARGET"
rm -f "$TMPFILE"

say "[80] Sudo reprompt hardening applied successfully"```

## File: ./sec-init-repo.md
```
```

## File: ./secure-init.sh
```
#!/usr/bin/env bash
# secure-init.sh â€” main orchestrator for modular YubiKey/FIDO2 hardening framework
# Run as your normal user; all privileged operations occur inside modules via sudo.
# --------------------------------------------------------------

set -euo pipefail

# --- Setup logging directory ---
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/secure-init"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/secure-init.log"

exec > >(tee -a "$LOGFILE") 2>&1

say(){
    echo -e "\n[ $(date '+%F %T') ] $*"
}

ERR(){
    echo -e "\n[ERROR] $*"
    exit 1
}

say "Starting secure-init orchestrator"
say "Modules directory: $BASE_DIR/modules"


# --- Preflight sanity checks ---
[[ -d "$BASE_DIR/modules" ]] || ERR "modules/ directory missing."

command -v sudo >/dev/null || ERR "sudo is required."
sudo -v || ERR "User is not in sudoers or sudo not available."


# --- Discover modules ---
MODULES=()

# numeric modules first
while IFS= read -r -d '' f; do
    MODULES+=("$f")
done < <(find "$BASE_DIR/modules" -maxdepth 1 -type f -name '[0-9][0-9]_*.sh' -print0 | sort -z)

# finish.sh always runs last
if [[ -f "$BASE_DIR/modules/finish.sh" ]]; then
    MODULES+=("$BASE_DIR/modules/finish.sh")
fi

say "Modules discovered in execution order:"
for m in "${MODULES[@]}"; do
    echo "  â†’ $(basename "$m")"
done


# --- Export safe environment for modules ---
export LOG_DIR LOGFILE BASE_DIR


# --- Execute modules in order ---
for module in "${MODULES[@]}"; do
    say "Running module: $(basename "$module")"
    # shellcheck disable=SC1090
    source "$module"
    say "Completed module: $(basename "$module")"
done

say "secure-init complete."
```

## File: ./.version
```
0.1.0
```

