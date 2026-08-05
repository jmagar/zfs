#!/bin/bash
# shellcheck disable=SC2154,SC2034
#set -x
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Script for snapshoting and/or replication a zfs dataset locally or remotely using zfs or rsync depending on the destination         # #
# #   (needs Unraid 6.12 or above)                                                                                                        # #
# #   by - SpaceInvaderOne                                                                                                                # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
#
# Main Variables
#
####################
#
#Unraid notifications during process (sent to Unraid gui etc)
notification_type="all"  # set to "all" for both success & failure, to "error"for only failure or "none" for no notices to be sent.
notify_tune="yes"  # as well as a notifiction, if sucessful it will play the Mario "achievment tune" or failure StarWars imperial march tune on beep speaker!
                   # sometimes good to have an audiable notification!! Set to "no" for silence. (this function your server needs a beep speaker)
#
####################
# Source for snapshotting and/or replication
source_pool="source_zfs_pool_name"  #this is the zpool in which your source dataset resides (note the does NOT start with /mnt/)
source_dataset="dataset_name"   #this is the name of the dataset you want to snapshot and/or replicate
                                #If using auto snapshots souce pool CAN NOT contain spaces. This is because sanoid config doesnt handle them
source_dataset_auto_select="no"  # Set to "no" to snapshot and replicate only the specified source_dataset, "yes" to auto-select all datasets for these operations
source_dataset_auto_select_exclude_prefix="backup_"	# Prefix to exclude certain datasets from auto-selection. Leave empty to disable exclusion
source_dataset_auto_select_excludes=(
	# List of dataset names to be excluded from auto-selection for snapshotting and replication
	"excluded_dataset"
)
#
####################
#
#zfs snapshot settings
autosnapshots="yes" # set to "yes" to have script auto snapshot your source dataset. Set to "no" to skip snapshotting.
#
#snapshot retention policy (default below works well, but change to suit)
snapshot_hours="0"
snapshot_days="7"
snapshot_weeks="4"
snapshot_months="3"
snapshot_years="0"
#
####################
#
# remote server variables (leave as is (set to "no") if not backing up to another server)
destination_remote="no" # set to "no" for local backup to "yes" for a remote backup (remote location should be accessable paired with ssh with shared keys)
remote_user="root"  #remote user (an Unraid server will be root)
remote_server="10.10.20.197" #remote servers name or ip
#
####################
#
### replication settings
#
replication="zfs"   #this is set to the method for how you want to have the sourcedataset replicated - "zfs" , "rsync" or "none"
#
##########
# zfs replication variables. You do NOT need these if replication set to "rsync" or "none"
destination_pool="dest_zfs_pool_name"  #this is the zpool in which your destination dataset will be created
parent_destination_dataset="dest_dataset_name" #this is the parent dataset in which a child dataset will be created containing the replicated data (zfs replication)
# For ZFS replication syncoid is used. The below variable sets some options for that.
# "strict-mirror" Strict mirroring that both mirrors the source and repairs mismatches (uses --force-delete flag).This will delete snapshots in the destination which are not in the source.
# "basic" Basic replication without any additional flags will not delete snapshots in destination if not in the source
syncoid_mode="strict-mirror"
#
##########
#
# rsync replication variables. You do not need these if replication set to zfs or no
parent_destination_folder="/mnt/user/rsync_backup" # This is the parent directory in which a child directory will be created containing the replicated data (rsync)
rsync_type="incremental" # set to "incremental" for dated incremental backups or "mirror" for mirrored backups
#
####################
#
# This function is to send messages to Unraid gui etc
#
unraid_notify() {
    local message="$1"
    local flag="$2"
    #
    # Check the notification_type variable
    if [[ "$notification_type" == "none" ]]; then
        return 0  # Exit the function if notification_type is set to 'none'
    fi
    #
    # If notification_type is set to 'error' and the flag is 'success', exit the function
    if [[ "$notification_type" == "error" && "$flag" == "success" ]]; then
        return 0  # Do not process success messages
    fi
    #
    # Determine the severity of the message based on the flag it received
    local severity
if [[ "$flag" == "success" ]]; then
    severity="normal"
    # Play success tune based on the value of 'notify_tune' and 'tune'
    if [[ "$notify_tune" == "yes" ]]; then
        if [[ "$tune" == "2" ]]; then
        # plays the old nokia ring tone (only used on snapshot sucess)
            beep -l 150 -f 1318.51022765 -n -l 150 -f 1174.65907167 -n -l 270 -f 739.988845423 -n -l 240 -f 830.60939516 -n -l 120 -f 1108.73052391 -n -l 150 -f 987.766602512 -n -l 270 -f 587.329535835 -n -l 240 -f 659.255113826 -n -l 150 -f 987.766602512 -n -l 120 -f 880.0 -n -l 270 -f 554.365261954 -n -l 240 -f 659.255113826 -n -l 1050 -f 880.0
        tune="1"
        else
        # plays the Mario achievement tune !! this is the main sucess tune used
            beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400
        fi
    fi
    else
        severity="warning"
        # Play failure tune if notify_tune is set to 'yes'
        if [[ "$notify_tune" == "yes" ]]; then
        # plays the Starwars imperial march tune !!
            beep -l 350 -f 392 -D 100 -n -l 350 -f 392 -D 100 -n -l 350 -f 392 -D 100 -n -l 250 -f 311.1 -D 100 -n -l 25 -f 466.2 -D 100 -n -l 350 -f 392 -D 100 -n -l 250 -f 311.1 -D 100 -n -l 25 -f 466.2 -D 100 -n -l 700 -f 392 -D 100 -n -l 350 -f 587.32 -D 100 -n -l 350 -f 587.32 -D 100 -n -l 350 -f 587.32 -D 100 -n -l 250 -f 622.26 -D 100 -n -l 25 -f 466.2 -D 100 -n -l 350 -f 369.99 -D 100 -n -l 250 -f 311.1 -D 100 -n -l 25 -f 466.2 -D 100 -n -l 700 -f 392 -D 100 -n -l 350 -f 784 -D 100 -n -l 250 -f 392 -D 100 -n -l 25 -f 392 -D 100 -n -l 350 -f 784 -D 100 -n -l 250 -f 739.98 -D 100 -n -l 25 -f 698.46 -D 100 -n -l 25 -f 659.26 -D 100 -n -l 25 -f 622.26 -D 100 -n -l 50 -f 659.26 -D 400 -n -l 25 -f 415.3 -D 200 -n -l 350 -f 554.36 -D 100 -n -l 250 -f 523.25 -D 100 -n -l 25 -f 493.88 -D 100 -n -l 25 -f 466.16 -D 100 -n -l 25 -f 440 -D 100 -n -l 50 -f 466.16 -D 400 -n -l 25 -f 311.13 -D 200 -n -l 350 -f 369.99 -D 100 -n -l 250 -f 311.13 -D 100 -n -l 25 -f 392 -D 100 -n -l 350 -f 466.16 -D 100 -n -l 250 -f 392 -D 100 -n -l 25 -f 466.16 -D 100 -n -l 700 -f 587.32
       fi
    fi
    #
    # Call the Unraid notification script
    /usr/local/emhttp/webGui/scripts/notify -s "Backup Notification" -d "$message" -i "$severity"
}
#
####################
#
# This function performs pre-run checks.
pre_run_checks() {
  # check for essential utilities
  if [ ! -x "$(which zfs)" ]; then
    msg='ZFS utilities are not found. This script is meant for Unraid 6.12 or above (which includes ZFS support). Please ensure you are using the correct Unraid version.'
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  if [ ! -x /usr/local/sbin/sanoid ]; then
    msg='Sanoid is not found or not executable. Please install Sanoid and try again.'
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  if [ "$replication" = "zfs" ] && [ ! -x /usr/local/sbin/syncoid ]; then
    msg='Syncoid is not found or not executable. Please install Syncoid plugin and try again.'
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  # check if the dataset and pool exist
  if ! zfs list -H "${source_path}" &>/dev/null; then
    msg="Error: The source dataset '${source_dataset}' does not exist."
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  # check if autosnapshots is set to "yes" and source_dataset has a space in its name
  if [[ "${autosnapshots}" == "yes" && "${source_dataset}" == *" "* ]]; then
    msg="Error: Autosnapshots is enabled and the source dataset name '${source_dataset}' contains spaces. Rename the dataset without spaces and try again. This is because although ZFS does support spaces in dataset names sanoid config file doesnt parse them correctly"
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  local used
  used=$(zfs get -H -o value used "${source_path}")
  if [[ ${used} == 0B ]]; then
    msg="The source dataset '${source_path}' is empty. Nothing to replicate."
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  # Traversal is checked for local runs too: parent_destination_folder reaches
  # `rsync --delete`, where a ".." component could delete outside the intended
  # destination regardless of whether the destination is remote. Matched as a path
  # component so legitimate names with consecutive periods (media..archive) pass.
  local _traversal_check
  for _traversal_check in "$parent_destination_folder" "$destination_pool" \
                          "$parent_destination_dataset" "$source_pool" "$source_dataset"; do
    case "$_traversal_check" in
      ..|../*|*/../*|*/..)
        msg="Error: destination settings may not contain a '..' path component: ${_traversal_check}"
        echo "$msg"
        unraid_notify "$msg" "failure"
        exit 1
        ;;
    esac
  done
  #
  if [ "$destination_remote" = "yes" ]; then
    echo "Replication target is a remote server. I will check it is available..."
    # This script has no validation library, and these values are embedded into
    # quoted remote commands sent over ssh, so a quote, backslash, backtick or $ in
    # them would break out of that quoting and run on the remote host.
    # source_pool/source_dataset are included because update_paths builds
    # destination_rsync_location out of them, and that value is interpolated into a
    # remotely double-quoted word where $ and backticks are still live.
    # The shell-metacharacter set is deliberately wider than the characters that can
    # escape the quoting used today: it keeps the guard valid if a future edit changes
    # or drops a surrounding quote at one of the ssh call sites.
    local _remote_unsafe
    for _remote_unsafe in "$parent_destination_folder" "$destination_pool" \
                          "$parent_destination_dataset" "$source_pool" "$source_dataset"; do
      case "$_remote_unsafe" in
        *[\'\"\`\$\\\;\&\|\<\>]*)
          msg="Error: destination settings may not contain shell metacharacters when replicating to a remote host: ${_remote_unsafe}"
          echo "$msg"
          unraid_notify "$msg" "failure"
          exit 1
          ;;
        *[[:cntrl:]]*)
          msg="Error: destination settings may not contain control characters: ${_remote_unsafe}"
          echo "$msg"
          unraid_notify "$msg" "failure"
          exit 1
          ;;
      esac
    done
    # ssh takes "user@host" as a single argv element, so a leading '-' would be parsed
    # as an ssh option (e.g. -oProxyCommand=...) rather than a destination.
    case "${remote_user}" in
      -*|*[\'\"\`\$\\\;\&\|\<\>[:cntrl:]]*)
        msg="Error: remote_user must not begin with '-' or contain shell metacharacters: ${remote_user}"
        echo "$msg"
        unraid_notify "$msg" "failure"
        exit 1
        ;;
    esac
    case "${remote_server}" in
      -*|*[\'\"\`\$\\\;\&\|\<\>[:cntrl:]]*)
        msg="Error: remote_server must not begin with '-' or contain shell metacharacters: ${remote_server}"
        echo "$msg"
        unraid_notify "$msg" "failure"
        exit 1
        ;;
    esac
    # Attempt an SSH connection. If it fails, print an error message and exit.
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${remote_user}@${remote_server}" echo 'SSH connection successful' &>/dev/null; then
      msg='SSH connection failed. Please check your remote server details and ensure ssh keys are exchanged.'
      echo "$msg"
      unraid_notify "$msg" "failure"
      exit 1
    fi
  else
    echo "Replication target is a local/same server."
  fi
  #
  # check script configuration variables
  if [ "$replication" != "zfs" ] && [ "$replication" != "rsync" ] && [ "$replication" != "none" ]; then
    msg="$replication is not a valid replication method. Please set it to either 'zfs', 'rsync', or 'none'."
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi

  if [ "$autosnapshots" != "yes" ] && [ "$autosnapshots" != "no" ]; then
    msg="The 'autosnapshots' variable is not set to a valid value. Please set it to either 'yes' or 'no'."
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  if [ "$destination_remote" != "yes" ] && [ "$destination_remote" != "no" ]; then
    msg="The 'destination_remote' variable is not set to a valid value. Please set it to either 'yes' or 'no'."
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  if [ "$destination_remote" = "yes" ]; then
    if [ -z "$remote_user" ] || [ -z "$remote_server" ]; then
      msg="The 'remote_user' and 'remote_server' must be set when 'destination_remote' is set to 'yes'."
      echo "$msg"
      unraid_notify "$msg" "failure"
      exit 1
    fi
  fi
  #
  if [ "$replication" = "none" ] && [ "$autosnapshots" = "no" ]; then
    msg='Both replication and autosnapshots are set to "none". Please configure them so that the script can perform some work.'
    echo "$msg"
    unraid_notify "$msg" "failure"
    exit 1
  fi
  #
  if [ "$replication" = "rsync" ]; then
    if [ "$rsync_type" != "incremental" ] && [ "$rsync_type" != "mirror" ]; then
      msg='Invalid rsync_type. Please set it to either "incremental" or "mirror".'
      echo "$msg"
      unraid_notify "$msg" "failure"
      exit 1
    fi
  fi
  # If all checks passed print below
  echo "All pre-run checks passed. Continuing..."
}
#
####################
#
# This function will build a Sanoid config file for use with the script
create_sanoid_config() {
  # only make config if autosnapshots is set to "yes"
  if [ "${autosnapshots}" != "yes" ]; then
    return
  fi
  #
  # check if the configuration directory exists, if not create it
  if [ ! -d "${sanoid_config_complete_path}" ]; then
    mkdir -p "${sanoid_config_complete_path}"
  fi
  #
  # check if the sanoid.defaults.conf file exists in the configuration directory, if not copy it from the default location
  if [ ! -f "${sanoid_config_complete_path}sanoid.defaults.conf" ]; then
    cp /etc/sanoid/sanoid.defaults.conf "${sanoid_config_complete_path}sanoid.defaults.conf"
  fi
  #
  # check if a configuration file has already been created from a previous run, if so exit the function
  if [ -f "${sanoid_config_complete_path}sanoid.conf" ]; then
    return
  fi
#
# this  creates the new configuration file based off variables for retention
  {
    echo "[${source_path}]"
    echo "use_template = production"
    echo "recursive = yes"
    echo ""
    echo "[template_production]"
    echo "hourly = ${snapshot_hours}"
    echo "daily = ${snapshot_days}"
    echo "weekly = ${snapshot_weeks}"
    echo "monthly = ${snapshot_months}"
    echo "yearly = ${snapshot_years}"
    echo "autosnap = yes"
    echo "autoprune = yes"
  } > "${sanoid_config_complete_path}sanoid.conf"
}
#
####################
#
# This fuction will autosnapshot the source dataset using Sanoid
autosnap() {
  # check if autosnapshots is set to "yes" before creating snapshots
  if [[ "${autosnapshots}" == "yes" ]]; then
    # Create the snapshots on the source directory using Sanoid if required
    echo "creating the automatic snapshots of ${source_path} using sanoid based off retention policy"
    # check the exit status of the sanoid command
    if /usr/local/sbin/sanoid --configdir="${sanoid_config_complete_path}" --take-snapshots; then
      tune="2"
      unraid_notify "Automatic snapshot creation using Sanoid was successful for source: ${source_path}" "success"
    else
      unraid_notify "Automatic snapshot creation using Sanoid failed for source: ${source_path}" "failure"
    fi
  #
  else
    echo "Autosnapshots are not set to 'yes', skipping..."
  fi
}
#
####################
#
# This fuction will autoprune the source dataset using sanoid
autoprune() {
  # rheck if autosnapshots is set to "yes" before creating snapshots
  if [[ "${autosnapshots}" == "yes" ]]; then
   echo "pruning the automatic snapshots of ${source_path} using sanoid based off retention policy"
# run Sanoid to prune snapshots based on retention policy
/usr/local/sbin/sanoid --configdir="${sanoid_config_complete_path}" --prune-snapshots
  else
    echo "Autosnapshots are not set to 'yes', skipping..."
  fi
}
#
####################
#
# This function  does the zfs replication
zfs_replication() {
  # Check if replication method is set to ZFS
  if [ "$replication" = "zfs" ]; then
    # Check if the destination location was set to remote
    if [ "$destination_remote" = "yes" ]; then
      destination="${remote_user}@${remote_server}:${zfs_destination_path}"
      # check if the parent destination ZFS dataset exists on the remote server. If not, create it.
      # shellcheck disable=SC2029 # client-side expansion is intended: the dataset variables only exist locally
      if ! ssh "${remote_user}@${remote_server}" "if ! zfs list -o name -H '${destination_pool}/${parent_destination_dataset}' &>/dev/null; then zfs create '${destination_pool}/${parent_destination_dataset}'; fi"; then
        unraid_notify "Failed to check or create ZFS dataset on remote server: ${destination}" "failure"
        return 1
      fi
    else
      destination="${zfs_destination_path}"
      # check if the parent destination ZFS dataset exists locally. If not, create it.
      if ! zfs list -o name -H "${destination_pool}/${parent_destination_dataset}" &>/dev/null; then
        if ! zfs create "${destination_pool}/${parent_destination_dataset}"; then
          unraid_notify "Failed to check or create local ZFS dataset: ${destination_pool}/${parent_destination_dataset}" "failure"
          return 1
        fi
      fi
    fi
    # calc which syncoid flags to use, based on syncoid_mode
    local -a syncoid_flags=("-r")
    case "${syncoid_mode}" in
      "strict-mirror")
       syncoid_flags+=("--delete-target-snapshots" "--force-delete")
        ;;
      "basic")
        # No additional flags other than -r
        ;;
      *)
        echo "Invalid syncoid_mode. Please set it to 'strict-mirror', or 'basic'."
        exit 1
        ;;
    esac
    #
    # Use syncoid to replicate snapshot to the destination dataset
    echo "Starting ZFS replication using syncoid with mode: ${syncoid_mode}"
    if /usr/local/sbin/syncoid "${syncoid_flags[@]}" "${source_path}" "${destination}"; then
      if [ "$destination_remote" = "yes" ]; then
        unraid_notify "ZFS replication was successful from source: ${source_path} to remote destination: ${destination}" "success"
      else
        unraid_notify "ZFS replication was successful from source: ${source_path} to local destination: ${destination}" "success"
      fi
    else
      unraid_notify "ZFS replication failed from source: ${source_path} to ${destination}" "failure"
      return 1
    fi
  else
    echo "ZFS replication not set. Skipping ZFS replication."
  fi
}
#
####################
#
# These below functions do the rsync replication
#
# Gets the most recent backup to compare against (used by below funcrions)
get_previous_backup() {
    if [ "$rsync_type" = "incremental" ]; then
        # Pick the newest backup that is not the one being written now. Selecting by
        # position instead ("2nd newest") is only correct once the in-progress dated
        # directory exists, so the parent dataset -- rsynced before that mkdir runs --
        # would link against a two-generations-old base and needlessly re-copy a whole
        # generation, while its children linked correctly. Excluding by name is
        # position-independent and right for both.
        # Only dated backup directories are candidates. rsync exits 0 when handed a
        # --link-dest that is not a directory, so a stray README or lost+found sorting
        # above the real backups would silently turn every run into a full copy.
        local dated_glob='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9]'
        local dated_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$'
        if [ "$destination_remote" = "yes" ]; then
            echo "Listing previous backups on ${remote_user}@${remote_server}:${destination_rsync_location}"
            # The remote side runs no pipeline, so ssh reports ls's own status rather
            # than head's; filtering happens locally. Exit 3 means the destination does
            # not exist yet, which is normal on a first run. Any other non-zero is a
            # real failure -- an unreadable or unmounted destination would otherwise be
            # indistinguishable from "no previous backup" and would silently downgrade
            # every run to a full copy.
            local remote_listing=""
            local listing_status=0
            # shellcheck disable=SC2029 # client-side expansion is intended: the destination path only exists locally
            # Lists directories only: a date-shaped regular file would otherwise be
            # accepted as a backup, and rsync exits 0 on a non-directory --link-dest.
            # The trailing `exit 0` matters: with no subdirectories the loop's last
            # test fails and the command would otherwise report failure for a
            # perfectly valid empty destination. `[ -r . ]` is checked first because
            # a directory that is traversable but not readable produces the same
            # empty glob, and would otherwise be reported as success.
            remote_listing=$(ssh "${remote_user}@${remote_server}" "if [ ! -d \"${destination_rsync_location}\" ]; then exit 3; fi; cd \"${destination_rsync_location}\" || exit 4; [ -r . ] || exit 5; for e in */; do [ -d \"\$e\" ] && printf '%s\n' \"\${e%/}\"; done; exit 0") || listing_status=$?
            if [ "$listing_status" -eq 0 ]; then
                previous_backup=$(printf '%s\n' "${remote_listing}" | grep -E "${dated_re}" | sort -r | grep -vxF "${backup_date}" | head -n 1)
            elif [ "$listing_status" -ne 3 ]; then
                echo "Warning: could not list previous backups on ${remote_server} (status ${listing_status}) - this run will be a full copy"
            fi
        elif [ -d "${destination_rsync_location}" ]; then
            # -H follows a symlinked backup root the way ls does; -type d and the dated
            # name pattern keep non-backup entries out of the candidate set. The status
            # is captured because -printf is GNU-only and an unreadable backup root
            # would otherwise look identical to "no previous backup", silently
            # downgrading every run to a full copy.
            local find_output=""
            local find_status=0
            find_output=$(find -H "${destination_rsync_location}" -mindepth 1 -maxdepth 1 -type d -name "${dated_glob}" -printf '%f\n') || find_status=$?
            if [ "$find_status" -eq 0 ]; then
                previous_backup=$(printf '%s\n' "${find_output}" | sort -r | grep -vxF "${backup_date}" | head -n 1)
            else
                echo "Warning: could not list previous backups in ${destination_rsync_location} (status ${find_status}) - this run will be a full copy"
            fi
        fi
    fi
}
#
rsync_replication() {
    local previous_backup  # declare variable

    # Function-scoped: a bare assignment leaked newline-only word splitting into
    # everything this script ran afterwards, including later dataset iterations.
    local IFS=$'\n'
    if [ "$replication" = "rsync" ]; then
        # Per-run unique, matching the Ubuntu script. With the old fixed name a
        # snapshot leaked by an earlier run made `zfs snapshot` fail forever, and any
        # attempt to clear it first risked destroying the snapshot of a concurrently
        # running backup mid-transfer.
        # $$ as well as the timestamp: two runs starting in the same second would
        # otherwise share a name, and the second would fail to snapshot and skip its
        # backup.
        local snapshot_name
        snapshot_name="rsync_snapshot_$(date +%s)_$$"
        if [ "$rsync_type" = "incremental" ]; then
            backup_date=$(date +%Y-%m-%d_%H%M)
            destination="${destination_rsync_location}/${backup_date}"
        else
            destination="${destination_rsync_location}"
        fi
        #
        do_rsync() {
            local snapshot_mount_point="$1"
            local rsync_destination="$2"
            local relative_dataset_path="$3"
            get_previous_backup
            local link_dest_path="${destination_rsync_location}/${previous_backup}${relative_dataset_path}"
            local -a link_dest=()
            if [ -n "$previous_backup" ]; then
                link_dest=("--link-dest=${link_dest_path}")
            fi
            # Log the link_dest value for debugging
            echo "Link dest value is: ${link_dest[*]}"
            #
            if [ "$destination_remote" = "yes" ]; then
                # Create the remote directory. Checked: an unreported mkdir failure
                # surfaced later as a confusing rsync error blaming the transfer.
                if [ "$rsync_type" = "incremental" ]; then
                    # shellcheck disable=SC2029 # client-side expansion is intended: the destination path only exists locally
                    if ! ssh "${remote_user}@${remote_server}" "mkdir -p \"${rsync_destination}\""; then
                        unraid_notify "Failed to create remote backup directory: ${remote_user}@${remote_server}:${rsync_destination}" "failure"
                        return 1
                    fi
                fi
                # Rsync the snapshot to the remote destination with link-dest
                #rsync -azvvv --delete "${link_dest[@]}" -e ssh "${snapshot_mount_point}/" "${remote_user}@${remote_server}:${rsync_destination}/"
                echo "Executing remote rsync: rsync -azvh --delete ${link_dest[*]} -e ssh \"${snapshot_mount_point}/\" \"${remote_user}@${remote_server}:${rsync_destination}/\""
                if ! rsync -azvh --delete "${link_dest[@]}" -e ssh "${snapshot_mount_point}/" "${remote_user}@${remote_server}:${rsync_destination}/"; then
                    unraid_notify "Rsync replication failed from source: ${source_path} to remote destination: ${remote_user}@${remote_server}:${rsync_destination}" "failure"
                    return 1
                fi
            else
                # Ensure the backup directory exists
                if [ "$rsync_type" = "incremental" ]; then
                    if ! mkdir -p "${rsync_destination}"; then
                        unraid_notify "Failed to create local backup directory: ${rsync_destination}" "failure"
                        return 1
                    fi
                fi
                # Rsync the snapshot to the local destination with link-dest
              #  rsync -avv --delete "${link_dest[@]}" "${snapshot_mount_point}/" "${rsync_destination}/"
              echo "Executing local rsync: rsync -avh --delete ${link_dest[*]} \"${snapshot_mount_point}/\" \"${rsync_destination}/\""
                if ! rsync -avh --delete "${link_dest[@]}" "${snapshot_mount_point}/" "${rsync_destination}/"; then
                    unraid_notify "Rsync replication failed from source: ${source_path} to local destination: ${rsync_destination}" "failure"
                    return 1
                fi
            fi
        }
        #
        echo "making a temporary zfs snapshot for rsync"
        if ! zfs snapshot "${source_path}@${snapshot_name}"; then
            unraid_notify "Failed to create ZFS snapshot for rsync: ${source_path}@${snapshot_name}" "failure"
            return 1
        fi
        #
        # Track failures rather than returning early, so the temporary snapshots are
        # always cleaned up. Previously every one of these results was discarded and
        # the run reported success even when the transfer had failed.
        #
        # Data failures and cleanup failures are tracked separately: a leaked snapshot
        # is a real problem, but reporting "the backup is incomplete" when every byte
        # transferred would send an operator into an unnecessary restore.
        local replication_failed=0
        local cleanup_failed=0
        #
        local snapshot_mount_point="/mnt/${source_path}/.zfs/snapshot/${snapshot_name}"
        do_rsync "${snapshot_mount_point}" "${destination}" "" || replication_failed=1
        #
        echo "deleting temporary snapshot"
        # Recorded, not returned: bailing out here skipped every child dataset and
        # left a dated directory holding only the parent's files, which the next run
        # then picked as its --link-dest base.
        if ! zfs destroy "${source_path}@${snapshot_name}"; then
            unraid_notify "Failed to delete ZFS snapshot after rsync: ${source_path}@${snapshot_name}" "failure"
            cleanup_failed=1
        fi
        #
        # A failed parent rsync almost always means the destination is full, unmounted
        # or unreachable, so attempting every child against it just wastes time and
        # leaves a half-written generation. Stop here, as the Ubuntu script does.
        if [ "$replication_failed" -ne 0 ]; then
            unraid_notify "Rsync ${rsync_type} replication failed for source: ${source_path} - child datasets were skipped and the backup at ${destination} is incomplete" "failure"
            return 1
        fi
        #
        # Replication for child sub-datasets
        local child_datasets=""
        local dataset_listing
        # Captured before the pipe: `zfs list | tail` reports tail's status, so a
        # failed listing would look like "no children" and back up the parent alone
        # while reporting a fully successful run.
        if dataset_listing=$(zfs list -r -H -o name "${source_path}"); then
            child_datasets=$(printf '%s\n' "${dataset_listing}" | tail -n +2)
        else
            unraid_notify "Failed to list child datasets of ${source_path} - child datasets were not replicated" "failure"
            replication_failed=1
        fi
        #
        for child_dataset in ${child_datasets}; do
            local relative_path
            relative_path="${child_dataset#"${source_path}/"}"
            echo "making a temporary zfs snapshot (child) for rsync"
            if ! zfs snapshot "${child_dataset}@${snapshot_name}"; then
                unraid_notify "Failed to create ZFS snapshot for child dataset: ${child_dataset}@${snapshot_name}" "failure"
                replication_failed=1
                continue
            fi
            snapshot_mount_point="/mnt/${child_dataset}/.zfs/snapshot/${snapshot_name}"
            child_destination="${destination}/${relative_path}"
            do_rsync "${snapshot_mount_point}" "${child_destination}" "/${relative_path}" || replication_failed=1
            # A leaked snapshot breaks the next run's snapshot of the same child.
            if ! zfs destroy "${child_dataset}@${snapshot_name}"; then
                unraid_notify "Failed to delete ZFS snapshot for child dataset: ${child_dataset}@${snapshot_name}" "failure"
                cleanup_failed=1
            fi
        done
        #
        # Only report success once every dataset (main and child) actually succeeded.
        if [ "$replication_failed" -ne 0 ]; then
            unraid_notify "Rsync ${rsync_type} replication finished with errors for source: ${source_path} - backup at ${destination} is incomplete" "failure"
            return 1
        fi
        if [ "$cleanup_failed" -ne 0 ]; then
            unraid_notify "Rsync ${rsync_type} replication of ${source_path} completed, but temporary snapshots could not be removed - the backup at ${destination} is complete" "failure"
            return 1
        fi
        if [ "$destination_remote" = "yes" ]; then
            unraid_notify "Rsync ${rsync_type} replication was successful from source: ${source_path} to remote destination: ${remote_user}@${remote_server}:${destination}" "success"
        else
            unraid_notify "Rsync ${rsync_type} replication was successful from source: ${source_path} to local destination: ${destination}" "success"
        fi
    fi
}

####################
#
# Update configs for specific dataset
#
update_paths() {
    local source_dataset_name="$1"

    source_dataset=$source_dataset_name
    source_path="$source_pool"/"$source_dataset"
    zfs_destination_path="$destination_pool"/"$parent_destination_dataset"/"$source_pool"_"$source_dataset"
    destination_rsync_location="$parent_destination_folder"/"$source_pool"_"$source_dataset"
    sanoid_config_complete_path="$sanoid_config_dir""$source_pool"_"$source_dataset"/
}
#
####################
#
# This function iterates over selected datasets to perform snapshotting and replication tasks
#
run_for_each_dataset() {

  # Array to hold dataset names for processing
  declare -a dataset_names

  if [[ "$source_dataset_auto_select" == "no" ]]; then
    # Directly use the specified dataset if auto-selection is disabled
    selected_source_datasets=("$source_dataset")
  else
    # Filter datasets based on exclusion rules if auto-selection is enabled
    local excludes_str=" ${source_dataset_auto_select_excludes[*]} "
    if [[ -z "$source_dataset_auto_select_exclude_prefix" ]]; then
      # Select all datasets if no exclusion prefix is specified
      while IFS= read -r line; do
        # Extract dataset name
        dataset_name=$(echo "$line" | awk -F'/' '{print $NF}')
        if [[ "$excludes_str" != *" $dataset_name "* ]]; then
          # Add dataset to the list if not excluded
          selected_source_datasets+=("$line")
        else
          echo "Exclude dataset $dataset_name"
        fi
        done < <(zfs list -r -o name -H $source_pool | awk -F'/' -v pool="$source_pool" '($0 ~ pool && NF==2) {print $2}')
    else
      # Exclude datasets starting with the specified prefix
      echo "Skipping datasets with names starting with {$source_dataset_auto_select_exclude_prefix}"
      while IFS= read -r line; do
        # Extract dataset name
        dataset_name=$(echo "$line" | awk -F'/' '{print $NF}')
        if [[ "$excludes_str" != *" $dataset_name "* ]]; then
          # Add dataset to the list if not excluded
          selected_source_datasets+=("$line")
      else
        echo "Exclude dataset $dataset_name"
      fi
      done < <(zfs list -r -o name -H $source_pool | awk -F'/' -v pool="$source_pool" -v prefix="$source_dataset_auto_select_exclude_prefix" '($0 ~ pool && NF==2 && $2 !~ ("^" prefix)) {print $2}')
    fi
  fi
  echo "Selected datasets:"
  printf '%s\n' "${selected_source_datasets[@]}"

  # Perform pre-run checks, create sanoid configs, snapshot, prune, and replicate for each selected dataset.
  for source_dataset_name in "${selected_source_datasets[@]}"; do
    update_paths "$source_dataset_name"
    echo "Performing pre-run checks for $source_dataset_name"
    pre_run_checks
    echo "Creating sanoid config for $source_dataset_name"
    create_sanoid_config
  done

  for source_dataset_name in "${selected_source_datasets[@]}"; do
    update_paths "$source_dataset_name"
    echo "Performing autosnapshot for $source_dataset_name"
    autosnap
  done

  # Replication failures are propagated: previously every return value here was
  # discarded, so the script exited 0 even when every dataset had failed and any
  # cron wrapper or monitoring keyed on exit status saw a clean run.
  local failed_datasets=0
  for source_dataset_name in "${selected_source_datasets[@]}"; do
    update_paths "$source_dataset_name"
    echo "Performing autoprune for $source_dataset_name"
    autoprune
    echo "Performing rsync replication for $source_dataset_name"
    rsync_replication || failed_datasets=$((failed_datasets + 1))
    echo "Performing ZFS replication for $source_dataset_name"
    zfs_replication || failed_datasets=$((failed_datasets + 1))
  done

  if [ "$failed_datasets" -ne 0 ]; then
    echo "ERROR: ${failed_datasets} replication task(s) failed - see errors above"
    return 1
  fi
}

#
########################################
#
# Execute the main function to start the process
run_for_each_dataset