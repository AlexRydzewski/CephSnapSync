#!/bin/bash

VERSION="0.1.0"

# Define defaults constant
#CONFIG_FILE=    				                    #global config for script to move other constants to it in the future
INTERVAL="82800"                                    #minimum time from last snap to create new snap
#TRANSFER_MODE=""                                   # [ direct|through ] (direct by default) # How data is transfer
WORKER_GROUP="some-ceph"                            # Group name for simultaneously run several instances with different 
                                                    # configuration

        ############    MASTER    ############
MASTER_SSH=""                                       # Compose by the script. Manual set not recommended.
                                                    # It is better to set cluster and ssh variables which are below
MASTER_ARG=""                                       # or pass to the script corresponding arguments. The same for SLAVE.
        #----------- SSH  related -----------#
#MASTER_SSH_HOST=""                                 # If SSH_HOST(name) is set, the script will try connect
#MASTER_SSH_USER=""                                 # to Master through ssh. The same for SLAVE.
#MASTER_SSH_KEY=""
        #----------- CEPH related -----------#
#MASTER_HOST=""                                     ## [ * ] (localhost" by default)
MASTER_FSID="11exxxxx-0e46-xxxx-8ffa-89bxxxxx3474"  
#MASTER_CONF_DIR=                                   
MASTER_CONF="/etc/ceph/ceph.conf"                   
#MASTER_USER=                                        
MASTER_KEYRING="/etc/ceph/ceph.client.admin.keyring" 
#MASTER_KEY=                                         
#MASTER_POOL=""                                      
#MASTER_IMAGE_LIVE=
MASTER_MIN_SNAPS="3"
MASTER_SNAP_LIFE="259200"
        ############    SLAVE    ############
SLAVE_SSH=""                                       # Compose by the script. Manual set not recommended.
                                                    # It is better to set cluster and ssh variables which are below
SLAVE_ARG=""                                       # or pass to the script corresponding arguments. The same for MASTER
        #----------- SSH  related -----------#
#SLAVE_SSH_HOST=""                                  # If SSH_HOST(name) is set, the script will try connect
#SLAVE_SSH_USER=""                                  # to the Backup through ssh. The same for MASTER.
#SLAVE_SSH_KEY=""
        #----------- CEPH related -----------#
#SLAVE_HOST=
#SLAVE_FSID=
#SLAVE_CONF=
#SLAVE_USER=
#SLAVE_KERING=
#SLAVE_KEY=
SLAVE_POOL="backup-pool"
#SLAVE_IMAGE_LIVE=
SLAVE_MIN_SNAPS="10"                                
SLAVE_SNAP_LIFE="864000"                            # Overhead maybe. For increase script speed and optimization

        ######### Program environment #########
PROG_NAME="rbd_backup"
PID_FILE="/var/run/$PROG_NAME/${PROG_NAME}-$$.pid"

        ########## event processing ##########
TOLERANCE="3"                                        # [ 3-5 ] Shifted by 3 from 0.  Wrong value may cause script to stop
VERBOSITY="2"                                        # [ 0-6 ] Inverted for logging. with 
MSG_BUFFER_LEVEL="0"
LOG_FILE="/var/log/$PROG_NAME/${PROG_NAME}.log"
FUNC_DELIM=":"
ITEM_DELIM=","

__save_pid () {
# + Messages for high verbosity
    [ ! -z "$(dirname "$PID_FILE")" ] && [ ! -d "$(dirname "$PID_FILE")" ] &&
    ! result="$(mkdir -p "$(dirname "$PID_FILE")" 2>&1)" && __event_processing +- "Cannot create directory '$(dirname "$PID_FILE")'" 5
    echo $$ > "$PID_FILE"
}

# Check if pid exist but program not running
__check_pid () {
    [ -z $1 ] &&
      { for pid_file in $(find /var/run/$PROG_NAME -type f); do
         { [ "$(ps -p $(cat $pid_file) -o comm=)" != "$PROG_NAME" ] && 
             { __event_processing +- "Stored pid '$(cat $pid_file)' found in file '$pid_file' but the process is not running. Remove the pid file" 3
               rm "$pid_file"; } || __event_processing +- "Another instanse is running" 5; }
        done; __save_pid; return; }
    [ -f "$PID_FILE" ] &&
      { ! pidof "$PROG_NAME" && __event_processing +- "Stored pid found but process not. Remove old pid '$(cat $PID_FILE)'" 3
        rm "$PID_FILE" || __event_processing +- "Another instanse is running" 5; }
    __save_pid
}

__set_tolerance () {
    [ ! -z "$1" ] && 
        { [ ! -z "${1/[0-3]}" ] &&
        __event_processing +- "Unknow --force mode $1. Set default" 3; } ||
        { TOLERANCE=$(( $1+3 )); return; }
    [ -z "$TOLERANCE" ] || [ ! -z "${TOLERANCE/[3-5]}" ] && TOLERANCE="3"
    return 0
}

__set_verbosity () {
    # Script operate of inverted verbosity level for logging
    [ ! -z "$1" ] &&
        { [ ! -z "${1/[0-6]}" ] && __event_processing +- "Unknow --verbose mode $1. Set default" 3 ||
        { VERBOSITY=$(( 6-$1 )); return; }; }
    [ -z "$VERBOSITY" ] || [ ! -z "${VERBOSITY/[0-5]}" ] && VERBOSITY=2
    return 0
}

__log_stamp () {
    printf -- "%s %s %s" "$(date "+%b %e %T")" "$(hostname -s)" "${LOG_PROG_NAME}[$$]"
}

# Event processing. Print messages and execute tolerance.
__msg_buffer_add () {
    [ $2 -ge "$MSG_BUFFER_LEVEL" ] &&
        { [ "$delim" = " " ] && delim=""; [ ! -z "$msg_buffer" ] && msg_buffer="${msg_buffer}${delim} ${1}" || msg_buffer="$1"; }
}

# The variant For log file
__log () {
    [ $2 -lt $VERBOSITY ] && return
    [ -z $last_event_gravity ] && { printf -- "%s: %s" "$(__log_stamp)" "$1"; return; } # If first
    [ -z "$last_printed_gravity" ] &&                                                   # If not printed yet
        { [ ! -z "$msg_buffer" ] && printf -- "\n%s: %s$delim %s" "$(__log_stamp)" "$msg_buffer" "$1" ||
        printf -- "\n%s: %s" "$(__log_stamp)" "$1"; return; }
    [ "$2" -le "$last_printed_gravity" ] && # Remove && make print in one row to less ++ event # If printed alredy and less or eq for last 
        { [ -z "$3" ] &&
            { { [ -z "$delim" ] && printf -- "%s" "$1"; } || { [ "$delim" = " " ] && printf -- " %s" "$1"; } ||
            printf -- "$delim %s" "$1"; } ||#   and trivial 
        { [ ! -z "$msg_buffer" ] &&                                                      #   and not trivial
            printf -- "\n%s: %s$3 %s" "$(__log_stamp)" "$msg_buffer" "$1" || printf -- "\n%s: %s" "$(__log_stamp)" "$1"; }; } ||
                                                                                         # If printed alredy, greather than last
        { [ -z "$3" ] &&
            { { [ -z "$delim" ] && printf -- "%s" "$1"; } || { [ "$delim" = " " ] && printf -- " %s" "$1"; } ||
            printf -- "$delim %s" "$1"; } ||#   and trivial 
            #{ [ "$delim" = " " ] && printf -- " %s" "$1" || printf -- "$delim %s" "$1"; }; } #   and not trivial
            { [ ! -z "$msg_buffer" ] &&                                                       #   and not trivial
                printf -- "\n%s: %s$3 %s" "$(__log_stamp)" "$msg_buffer" "$1" || printf -- "\n%s: %s" "$(__log_stamp)" "$1"; }; }
    return 0
}

__msg_add () {
    [ "$2" -gt "$VERBOSITY" ] && [ "$2" -lt "$last_event_gravity" ] && 
        { [ ! -z "$msg_buffer" ] && printf -- "\n%s$delim %s" "$msg_buffer" "$1" || printf -- "\n%s" "$1"; return; }
    [ "$2" -ge "$VERBOSITY" ] && [ -z "$last_event_gravity" ] &&
        { [ ! -z "$msg_buffer" ] && printf -- "%s$delim %s" "$msg_buffer" "$1" || printf -- "%s" "$1"; return; }
    [ "$2" -eq $VERBOSITY ] && 
        { { [ "$delim" = " " ] && printf -- " %s" "$1"; }  ||
        { [ ! -z "$delim" ] && printf -- "$delim %s" "$1" || printf -- "%s" "$1"; }; }
    return 0
}

__set_delim () {
    [ -z "$last_event_gravity" ] && return
    [ "$1" -gt $last_event_gravity ] && delim="$FUNC_DELIM" || delim="$ITEM_DELIM"
}

__end () {
    last_printed_gravity=""
    __event_processing ++ "end" 3
    printf "\n"
    [ -f "$PID_FILE" ] && rm $PID_FILE
    [ -z $1 ] && exit 0 || exit $1
}

declare delims="$FUNC_DELIM$ITEM_DELIM"
__event_processing () {
    # Add delimeter manually set to delimeters list
    [ "${delims/$4}" = "$delims" ] && delims="${delims}${4}"

    # Remove parts from buffer of messages
    [ "$1" = "-" ] &&
        { [ ! -z $2 ] && 
            { [ ! -z "${2/[0-9]}" ] &&
                { msg_buffer="${msg_buffer%%["$delims"] "$2"*}"; msg_buffer="${msg_buffer%%$2*}"
                last_event_gravity=$3; } ||
                { msg_buffer=""; last_event_gravity=$2; }; } ||
            { msg_buffer=""; last_printed_gravity=""; }; return; }

    # Delimiter definition
    [ ! -z "$4" ] && delim="$4" || { [ "$1" = "++" ] && __set_delim $3; } || { [ "$1" = "+-" ] && delim=""; } ||
    { ([ "$1" = "+" ] && ([ -z $last_printed_gravity ] || [ $3 -ge $last_printed_gravity ])) && __set_delim $3 || delim=" "; }

    # Journaling and buffer filling
    [ "$1" = "++" ] && __log "$2" $3 "$delim" || __log "$2" $3  
    [ "$1" = "++" ] && __msg_buffer_add "$2" $3

    #  Set pointers for defining the order of output and format of messages
    [ $3 -ge $VERBOSITY ] &&
        { ([ "$1" = "++" ] && ([ -z $last_printed_gravity ] || [ "$3" -gt "$last_printed_gravity" ]) ||
        [ "$1" = "+" ] && ([ -z $last_printed_gravity ] || [ $3 -gt $last_printed_gravity ])) &&
        last_printed_gravity=$3; }
        [ "$1" = "++" ] && ([ ! -z $last_printed_gravity ] && [ $3 -lt $last_printed_gravity ]) && last_printed_gravity=""
    last_event_gravity="$3" 

    # Script execution tolerance control
    [ "$3" -le $TOLERANCE ] && return 0 || __end 1
}

__operation_add () {
    [ -z "$1" ] && return 1
    [ "$1" = "snap" ] || [ "$1" = "backup" ] || [ "$1" = "purge" ] || [ "$1" = "master-purge" ] || [ "$1" = "backup-purge" ] &&
        { OPERATIONS="$OPERATIONS $1"; return 0; }
    __event_processing +- "Unknow --alg mode $1." 5; return 1
}
    
__test_cluster () {
    __event_processing ++ "${1%A*}/test" 0
    __set_ref $1
    [ "${!_ssh_ref}" ] &&
        { __event_processing ++ "ssh" 1
        __event_processing + "host \"${!_ssh_host_ref}\"" -1
        ssh_con_result=$(${!_ssh_ref} exit 2>&1) &&
        __event_processing +- "- success" -1 ||
            { [ "$1" = "MASTER" ] && __event_processing +- "- fail" 5 || __event_processing +- "- fail" 4
            __event_processing -; return 1; }
        __event_processing - "ssh" 1; }
    __event_processing ++ "Connect" 1
    fsid="$(${!_ssh_ref} ceph ${!_arg_ref/"--pool ${!_pool_ref}"} fsid 2>&1)" &&
        __event_processing +- "- success" -1 ||
        { [ "$1" = "MASTER" ] && __event_processing +- "- fail" 5 || __event_processing +- "- fail" 4;
            __event_processing -; return 1; }
        __event_processing - "Connect" 1

    __event_processing ++ "FSID" 1 
    [ ! "${!_fsid_ref}" ] &&
        { __event_processing + "n/configured, Set" 0 "-"; __event_processing + "\"($fsid)\"" -1
        eval "$_fsid_ref"=\"$fsid\"; } ||
        { [ "${!_fsid_ref}" != "$fsid" ] &&
            { __event_processing + "(conf:${!_fsid_ref},cluster:$fsid)" -1; __event_processing +- "- mismatch" 5; } ||
            { __event_processing + "($fsid)" -1; __event_processing +- "- matches" -1; }; }
    # For avoid connection to the same cluster!
    [ "$1" = "SLAVE" ] &&
        { __event_processing ++ "Compare with master" 0; __event_processing + "($fsid)" -1
        [ "$SLAVE_FSID" = "$MASTER_FSID" ] &&
            { __event_processing +- "- identical" 5; __event_processing - ; return 1; } || __event_processing +- "- different" -1; }
    __event_processing - "FSID" 1

    # Getting health status 
    __event_processing ++ "Health" 1
    health=$(${!_ssh_ref} ceph ${!_arg_ref/--pool ${!_pool_ref}} health) &&
        [ "$1" = "MASTER" ] &&
            {
                { [ "${health%% *}" = "HEALTH_OK" ]   && __event_processing +- "- OK" 1; } ||
                { [ "${health%% *}" = "HEALTH_WARN" ] && __event_processing +- "- WARN" 3; } ||
                { [ "${health%% *}" = "HEALTH_ERR" ]  && __event_processing +- "- ERR" 4; };
               __event_processing -; } ||
            {
                { [ "${health%% *}" = "HEALTH_OK" ]   && __event_processing +- "- OK" -1; } ||
                { [ "${health%% *}" = "HEALTH_WARN" ] && __event_processing +- "- WARN" 2; } ||
                { [ "${health%% *}" = "HEALTH_ERR" ]  && __event_processing +- "- ERR" 3; }
               __event_processing -; } 
    __event_processing - "${1%A*}/test" 0
}

__get_raw_list () {
    # Will try get of raw list from pool
    __event_processing ++ "${1%A*}/getraw" 0
    __set_ref $1
    _raw_list="$(${!_ssh_ref} rbd ${!_arg_ref} ls 2>&1)" &&
        __event_processing +- "$([ "${!_pool_ref}" ] && echo " (${!_pool_ref})"): $(echo $_raw_list)" -1 ||
        { __event_processing +- "Pool \"${!_pool_ref}\" error" 3
        __event_processing +- "Ceph respond \"$(echo ${_raw_list})\"" -1
        { [ "$1" = "MASTER" ] &&
            __event_processing +- "stop " 5 ||
            __event_processing +- "Backup will not be perform" 4; return 1; }; }

    [ ! "$_raw_list" ] &&
        { [ "$1" = "MASTER" ] && __event_processing +- "- pool \"${!_pool_ref}\" is empty" 5 ||
        { __event_processing +- "- pool \"${!_pool_ref}\" is empty" 0; return 0; }; }

    eval "$_raw_list_ref"=\"$_raw_list\"
    __event_processing - "${1%A*}/getraw" 0
}

__set_ref () {
    _ssh_ref="${1}_SSH"
    _ssh_host_ref="${1}_SSH_HOST"
    _arg_ref="${1}_ARG"
    _pool_ref="${1}_POOL"
    _fsid_ref="${1}_FSID"
    _raw_list_ref="${1,,}_raw_list"
}

__compose_args () {
    local row
    _ref="${1}_HOST";    [ "${!_ref}" ] && row="$row --host=${!_ref}"
    _ref="${1}_CONF";    [ "${!_ref}" ] && row="$row --conf=${!_ref}"
    _ref="${1}_KEYRING"; [ "${!_ref}" ] && row="$row --keyring=${!_ref}"
    _ref="${1}_USER";    [ "${!_ref}" ] && row="$row --user=${!_ref}"
    _ref="${1}_KEY";     [ "${!_ref}" ] && row="$row --key=${!_ref}"
    _ref="${1}_POOL";    [ "${!_ref}" ] && row="$row --pool ${!_ref}"
    echo "$row"
}

__compose_ssh_command () {
    local row
    _ref="${1}_SSH_HOST"; [ "${!_ref}" ] && row="${!_ref}" || return 0
    _ref="${1}_SSH_USER"; [ "${!_ref}" ] && row="-l ${!_ref} $row"
    _ref="${1}_SSH_KEY";  [ "${!_ref}" ] && row="-i ${!_ref} $row"
    echo "ssh $row"
}

__create_master_snap () {
    __event_processing + "last" 2 
    master_last_snap=$($MASTER_SSH rbd snap $MASTER_ARG ls $1| tail -1 | sed -rn "s/^\s+?[0-9]+\s+([0-9]+).*/\1/p")
    { [ -z "$master_last_snap" ] && __event_processing +- "snaps absent" 2; } ||
    { __event_processing +- "\"$master_last_snap\"" 2 " " 
    # Check raw for changes from last snap
    __event_processing + "Interval" 1
    __event_processing + "($INTERVAL)" 1
    [ "$master_last_snap" -le "$(( $($MASTER_SSH date +%s) - $INTERVAL ))" ] && __event_processing + "exceeded" 2; } &&
        { snap_name=$(date +%s); __event_processing ++ "create \"$snap_name\"" 3
        snap_result=$(${MASTER_SSH} rbd snap ${MASTER_ARG} create $1@$snap_name 2>&1) &&
            __event_processing +- "..ed" 2 || { __event_processing +- " fail" 4; __event_processing +- "$snap_result" 0; }; } || 
            __event_processing +- "n/expired" 2 " "
}

__first_raw_backup () {
    __event_processing ++ "i/e" 3
    master_first_snap=$($MASTER_SSH rbd snap $MASTER_ARG ls $1| sed -rn "s/^\s+?[0-9]+\s+([0-9]+).*/\1/p" | sort -n -r | tail -1)
    __event_processing + "\"$master_first_snap\"" 3
    export_result=$($MASTER_SSH rbd $MASTER_ARG --no-progress export $1@$master_first_snap - | $SLAVE_SSH rbd $SLAVE_ARG --image-format 2 --no-progress import - $1 2>&1) &&
        { __event_processing + "..ed" 2; __event_processing ++ "snap" 2
        snap_result=$($SLAVE_SSH rbd snap $SLAVE_ARG create $1@$master_first_snap 2>&1) &&
            { __event_processing +- "..ed" 2 || __event_processing +- " fail" 4; }; } ||
            { __event_processing +- "fail" 4; __event_processing +- "$snap_result" 0; } # Do some action for next repair broken image
}

__remove_snap () {
    __event_processing + "remove \"$2\"" 3
    ${!_ssh_ref} rbd snap ${!_arg_ref} --no-progress rm "$1"@"$2"
    __event_processing +- "..ed" 2 
}

__remove_raw_backup () {
    __set_ref SLAVE
    # May be better get last snap for every operation?
    for snap in $($SLAVE_SSH rbd snap $SLAVE_ARG ls $1| tail -1 | sed -rn "s/^\s+?[0-9]+\s+([0-9]+).*/\1/p"); do
        __remove_snap $1 $snap
    done
    __event_processing ++ "rm/raw $1" 3
    $SLAVE_SSH rbd $SLAVE_ARG --no-progress rm "$1"
}

__diff_raw_backup () {
    __event_processing + "compare" 1
    master_last_snap=$($MASTER_SSH rbd snap $MASTER_ARG ls $1| tail -1 | sed -rn "s/^\s+?[0-9]+\s+([0-9]+).*/\1/p")
    __event_processing + "M/last \"$master_last_snap\"" 1
    backup_last_snap=$($SLAVE_SSH rbd snap $SLAVE_ARG ls $1| tail -1 | sed -rn "s/^\s+?[0-9]+\s+([0-9]+).*/\1/p")
    __event_processing + "B/last \"$backup_last_snap\"" 2
    #[ "$backup_last_snap" -ge "$master_last_snap" ] && { __event_processing +- "actual" 2 " "; return; }
    [ -z "$backup_last_snap" ] && __event_processing +- "n/present" 2 " " ||
      { [ "$backup_last_snap" -ge "$master_last_snap" ] && { __event_processing +- "actual" 2 " "; return; }
        # Get M snap list, Find in B last snap, Make export-diff/import-diff for all one by one
        __event_processing + "outdate" 2 " "; __event_processing + "search M/snap" 0
        for master_snap in $($MASTER_SSH rbd snap $MASTER_ARG ls $1| sed -rn "s/^\s+?[0-9]+\s+([0-9]+).*/\1/p"); do
            [ ! -z "$from_snap" ] &&
              { __event_processing ++ "e/i \"$master_snap\"" 3
                export_import_result=$($MASTER_SSH rbd $MASTER_ARG --no-progress export-diff --from-snap $from_snap $1@$master_snap - | $SLAVE_SSH rbd $SLAVE_ARG --no-progress import-diff - $1 2>&1) &&
                __event_processing +- "..ed" 2 || { __event_processing +- " fail" 3; break; }
                from_snap="$master_snap"; continue; } 
            [ "$master_snap" -eq "$backup_last_snap" ] && from_snap="$master_snap"
        done
        [ -z "$from_snap" ] && __event_processing ++ "n/suitable" 2 || { __event_processing +- "updated" 1 ":"; unset from_snap; return 0; }; }
    __event_processing ++ "purge backup" 2; __remove_raw_backup $1; __first_raw_backup "$1"
    __diff_raw_backup "$1"
    #__event_processing +- "updated" 1 ":"; unset from_snap
}

__get_snaps_list () {
    ${!_ssh_ref} rbd snap ${!_arg_ref} ls $1 | sed -rn "s/^\s+?[0-9]+\s+([0-9]+).*/\1/p"
}

__purge_snaps () {
    __event_processing ++ "${1%A*}/Purge" 0
    __set_ref $1
    _raw_list_ref="${1,,}_raw_list"
    _min_snaps_ref="${1}_MIN_SNAPS"
    _snap_life_ref="${1}_SNAP_LIFE"
    for raw in "${!args[@]}"; do
        __event_processing ++ "\"${args[raw]}\"" 2
        [ "${!_raw_list_ref}/${args[raw]}" = "${!_raw_list_ref}" ] &&
         __event_processing + "n/present" 2 ||
        { __event_processing + "present" 1
        [ ! "${#snaps_list[@]}" -gt 0 ] && local snaps_list=($(__get_snaps_list ${args[raw]}))
        [ "${#snaps_list[@]}" -gt "${!_min_snaps_ref}" ] &&
            { __event_processing + "abundantly" 2
            for (( c=0; c<$(( ${#snaps_list[@]}-${!_min_snaps_ref} )); c++ )); do
                __event_processing + "\"${snaps_list[c]}\"" 2
                [ "$(( ${snaps_list[c]} + ${!_snap_life_ref} ))" -lt $(${!_ssh_ref} date +%s) ] &&
                    { __event_processing + "aged" 2; __remove_snap "${args[raw]}" "${snaps_list[c]}"; } || __event_processing + "recent" 2
            done; } || __event_processing + "minimum" 2
        unset snaps_list; }
        [ $last_printed_gravity -gt 2 ] && __event_processing - "\"${args[raw]}\"" 0 || __event_processing - "\"${args[raw]}\"" 2
    done
    __event_processing - "${1%A*}/Purge" 0
}

# Print usage
__usage() {
echo -n "Create snaps for ceph rbd images on \"master\" cluster and backup them 
to another \"backup\" ceph cluster.

Usage: ${0} [[OPTION]...] [[image]...]

 Options:
    For ssh connections
      --[ master|backup ]-ssh-host []   Host for remote ssh connections to master/backup client host.
      --[ master|backup ]-ssh-user []   User for remote ssh connections to master/backup client host.
      --[ master|backup ]-ssh-key []    Public rsa key file for remote ssh connections to master/backup host.
      ?-direct-transfer                 Direct ssh transfer from master to backup even if both are
                                        connected by ssh.

    For CEPH connections
      --[ master|backup ]-host []       Hostname/IP of ceph monitor for connect to.
      --[ master|backup ]-user []       Name of ceph user.
      --[ master|backup ]-keyring []    Ceph Secure key file (keyring file).
      --[ master|backup ]-key []        Key for connect to ceph.
      --[ master|backup ]-pool []       RBD pool for work with it.
      --[ master|backup ]-fsid []       FSID of ceph cluster. Highly recommended set it for avoid
                                        annoyng mistakes. If fsid identical for master and backup.
    Algorithm options
      --[ master|backup ]-snap-life     Time in seconds for which will not be attempt to remove snap.
      --[ master|backup ]-min-snsps     Minimum counts of snaps for remove snap attempt.
      --[ master|backup ]-raw-life      For images that are not updated, the time after which they will be deleted.
                                        Indefinite by default.
      --alg [ variant ] --alg...        Variants are:
                                            snap - do master snap; backup - do backup; purge - cleaning master
                                                and backup snaps appropriate to --[master|backup]-snap-life
                                                and --[master|backup]-min-snaps;
                                            backup - mirroring snaps and images from master to backup;
                                            purge[-master|-backup] } - purge snaps and raws for master and backup or
                                                separately for each;
                                            ?zabbix - send to zabbix discovered data and results of operations for 
                                                specified raws. By default all operations will be performed.
      --onebyone                        Perform operations one by one for every image. By default every operation
                                        perform for all specified images.

    Proggram execute options
      -f, --force [ 0-2 ]               Execute tolerance. Script will stop if event be:
                                            0 - someting important; 1 - not critical;
                                            2 - critical (very dangerous! anybody unknow what will happen...)
      --program-name                    Set the program name for log and pid file name (/run/{program-name}/{program-name}.pid)
      --pid-file                        Default: /run/{program-name}/{program-name}.pid. Override '--program-name'.
      --simultaneous                    Allow several copy of program execute with the same configuration.

    Output and logging
      -v, --verbose [ 0-5 ]             Level of output information and/or logging. (Items echoed to 'verbose')
                                        From lower to upper level add info:
                                            0 - full silent; 1 - critical errors; 2 errors; 3 - operations;
                                            4 - operations info; functions; 5 - operations detail; function info;
                                            6 - full output
      --log-file []                     Print log to the file (default /var/log/{program-name}/{program-name}.log).
                                        Override '--program-name'.

                                        Make sure you have rights, because if not, log will be printed to stdout.
      ?-stdout                          Results will print to stdout. Format of output differ from log format,
                                        adapted for convenience of observation. Results will not be written to log file.
      ?-log-stdout                      Results ouput to stdout in log format. Results will not be written to log file.
      -d, --debug                       Runs script in BASH debug mode (set -x).


      -h, --help                        Display this help and exit.
      --version                         Output version information and exit.
  
"
}

# Iterate over options breaking -ab into -a -b when needed and --foo=bar into
# --foo bar
optstring=h
unset options
while (($#)); do
    case $1 in
        # If option is of type -ab
        -[!-]?*)
            # Loop over each character starting with the second
            for ((i=1; i < ${#1}; i++)); do
                c=${1:i:1}

                # Add current char to options
                options+=("-$c")

                # If option takes a required argument, and it's not the last char make
                # the rest of the string its argument
                if [[ $optstring = *"$c:"* && ${1:i+1} ]]; then
                    options+=("${1:i+1}")
                    break
                fi
           done
        ;;

        # If option is of type --foo=bar
        --?*=*) options+=("${1%%=*}" "${1#*=}") ;;
        # add --endopts for --
        --) options+=(--endopts) ;;
        # Otherwise, nothing special
        *) options+=("$1") ;;
    esac
    shift
done

set -- "${options[@]}"
unset options

# Print help if no arguments were passed.
# Uncomment to force arguments when invoking the script
#[[ $# -eq 0 ]] && set -- "--help"

while [[ $1 = -?* ]]; do
  case $1 in
    -h|--help) __usage >&2; exit 0 ;;
#    -h|--help) usage >&2; safeExit ;;
    --version) echo "$(basename $0) ${version}"; exit 0 ;;
#    --version) echo "$(basename $0) ${version}"; safeExit ;;
    #--mode) shift; RUN_MODE=${1} ;;
    --master-ssh-host) shift; MASTER_SSH_HOST=${1} ;;
    --master-ssh-user) shift; MASTER_SSH_USER=${1} ;;
    --master-ssh-key) shift; MASTER_SSH_KEY=${1} ;;
    --backup-ssh-host) shift; SLAVE_SSH_HOST=${1} ;;
    --backup-ssh-user) shift; SLAVE_SSH_USER=${1} ;;
    --backup-ssh-key) shift; SLAVE_SSH_KEY=${1} ;;
    --master-host) shift; MASTER_HOST=${1} ;;
    -C|--master-conf) shift; MASTER_CONF=${1} ;;
    -M|--master-keyring) shift; MASTER_KEYRING=${1} ;;
    -U|--master-user) shift; MASTER_USER=${1} ;;
    -K|--master-key) shift; MASTER_KEY=${1} ;;
    --backup-host) shift; SLAVE_HOST=${1} ;;
    -c|--backup-conf) shift; SLAVE_CONF=${1} ;;
    -b|--backup-keyring) shift; SLAVE_KEYRING=${1} ;;
    -u|--backup-user) shift; SLAVE_USER=${1} ;;
    -k|--backup-key) shift; SLAVE_KEY=${1} ;;
    --alg) shift; __operation_add ${1} ;;
    --prog-name) shift; PROG_NAME=${1} ;;
    --pid-file) shift; __check_pid ${1} ;;
    --log-file) shift; LOG_FILE=${1} ;;
    --verbose) shift; __set_verbosity ${1} ;;
    -f|--force) shift; __set_force_level ${1} ;;
    --endopts|"-- ") shift; break ;;
    -d|--debug) set -x ;;
    *) echo "invalid option '$1'"; shift ;;
  esac
  shift
done

# Store the remaining part as arguments.
args+=("$@")

### Start script
[ -z "$PROG_NAME" ] && PROG_NAME="$(basename ${0%.*})"
__set_verbosity; __set_tolerance
### PID!!!
#([ -z "$MODE" ] || [ "$MODE" = "daemon" ]) &&


__event_processing +- "start" 3

# Adapting ssh command
__event_processing +- "Adapting ssh command" -1
for side in "MASTER" "SLAVE"; do
    _ssh_ref="${side}_SSH"
    [ ! "${!_ssh_ref}" ] && declare "$_ssh_ref"="$(__compose_ssh_command $side)"
done

# Test MASTER Cluster
[ ! "$MASTER_ARG" ] && MASTER_ARG="$(__compose_args MASTER)"
__test_cluster MASTER
declare master_raw_list; __get_raw_list MASTER

# Set right condition for that...
[ ! "$MODE" = "snap" ] && 
    # Test SLAVE cluster
    { [ ! "$SLAVE_ARG" ] && SLAVE_ARG="$(__compose_args SLAVE)"
    declare backup_raw_list; 
    ! __test_cluster SLAVE || ! __get_raw_list SLAVE && SLAVE_STATE="fail"; }

# Create snapshots
[ -z "$OPERATIONS" ] || [ ! "${OPERATIONS/ snap}" = "$OPERATIONS" ] && 
    { __event_processing ++ "M/Snaps" 0
    for raw in ${!args[@]}; do
        __event_processing ++ "\"${args[raw]}\"" 2
        [ "${master_raw_list/${args[raw]}}" != "$master_raw_list" ] &&
            { __event_processing + "present" 1
            __create_master_snap ${args[raw]}; } || { unset args[raw]; __event_processing + "n/present" 2; }
        #[ $last_printed_gravity -gt 2 ] && __event_processing - "\"${args[raw]}\"" 0 || __event_processing - "\"${args[raw]}\"" 2
        ([ ! -z "$last_printed_gravity" ] && [ $last_printed_gravity -gt 2 ]) && 
	    __event_processing - "\"${args[raw]}\"" 0 || __event_processing - "\"${args[raw]}\"" 2
    done
    __event_processing - "M/Snaps" 0; }

[ "$OPERATIONS" = "snap" ] &&
    { last_printed_gravity=""; __event_processing ++ "end" 3; __end 0; }

[ "$SLAVE_STATE" = "fail" ] && { __event_processing +- "Skip backuping and purging due SLAVE cluster error" 4; }

# Backup routines
([ -z "$OPERATIONS" ] || [ ! "${OPERATIONS/ backup}" = "$OPERATIONS" ]) && [ ! "$SLAVE_STATE" = "fail" ] && 
    { __event_processing ++ "Copy" 0 
    for raw in ${!args[@]}; do
        __event_processing ++ "\"${args[raw]}\"" 2
        __event_processing + "Backup" 0 
        [ "${backup_raw_list/${args[raw]}}" = "$backup_raw_list" ] &&
            { __event_processing + "n/present" 2; __first_raw_backup ${args[raw]}; } || __event_processing + "present" 1; 
            __diff_raw_backup ${args[raw]};
        [ $last_printed_gravity -gt 2 ] && __event_processing - "\"${args[raw]}\"" 0 || __event_processing - "\"${args[raw]}\"" 2
    done
    __event_processing - "Copy" 0; }

# Delete old MASTER snaps
([ -z "$OPERATIONS" ] || [ ! "${OPERATIONS/ master-purge}" = "$OPERATIONS" ] || [ ! "${OPERATIONS/ purge}" = "$OPERATIONS" ]) &&
    [ ! "$SLAVE_STATE" = "fail" ] && __purge_snaps MASTER

# Delete old SLAVE snaps
([ -z "$OPERATIONS" ] || [ ! "${OPERATIONS/ backup-purge}" = "$OPERATIONS" ] || [ ! "${OPERATIONS/ purge}" = "$OPERATIONS" ]) && 
    [ ! "$SLAVE_STATE" = "fail" ] && __purge_snaps SLAVE 

# Final
__end


#/usr/bin/cceph-backup: line 387: [: -gt: unary operator expected
#/usr/bin/cceph-backup: line 388: [: -gt: unary operator expected
#/usr/bin/cceph-backup: line 599: [: -gt: unary operator expected

