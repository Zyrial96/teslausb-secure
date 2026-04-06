#!/bin/bash -eu

REPO=${REPO:-cimryan}
BRANCH=${BRANCH:-master}

# FIX: Basic validation for REPO and BRANCH to prevent command injection
if [[ "$REPO" =~ [\.\./] ]] || [[ "$REPO" =~ ^/ ]]; then
  echo "ERROR: Invalid REPO name. Cannot contain '..', '../', or start with '/'"
  exit 1
fi

if [[ "$BRANCH" =~ [\.\./] ]] || [[ "$BRANCH" =~ ^/ ]]; then
  echo "ERROR: Invalid BRANCH name. Cannot contain '..', '../', or start with '/'"
  exit 1
fi

ARCHIVE_SYSTEM=${ARCHIVE_SYSTEM:-none}
export INSTALL_DIR=${INSTALL_DIR:-/root/bin}

function check_variable () {
    local var_name="$1"
    if [ -z "${!var_name+x}" ]
    then
        echo "STOP: Define the variable $var_name like this: export $var_name=value"
        exit 1
    fi
}

# FIX: URL encoding function for safe GitHub downloads
function urlencode () {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) encoded+="$c" ;;
            *) printf -v o '%%%02x' "'$c"; encoded+="$o" ;;
        esac
    done
    echo "$encoded"
}

function get_script () {
    local local_path="$1"
    local name="$2"
    local remote_path="${3:-}"

    echo "Starting download for $local_path/$name"
    
    # FIX: URL-encode path components to prevent injection
    local encoded_remote_path
    if [[ -n "$remote_path" ]]; then
        encoded_remote_path=$(urlencode "$remote_path")/
    else
        encoded_remote_path=""
    fi
    local encoded_name
    encoded_name=$(urlencode "$name")
    
    # FIX: Use curl with -fsSL for fail on error, silent, show error, location
    if curl -fsSL -o "$local_path/$name" \
        "https://raw.githubusercontent.com/${REPO}/${BRANCH}/${encoded_remote_path}${encoded_name}"; then
        chmod +x "$local_path/$name"
        echo "Done"
    else
        echo "ERROR: Failed to download $name from GitHub"
        return 1
    fi
}

function install_rc_local () {
    local install_home="$1"

    if grep -q archiveloop /etc/rc.local
    then
        echo "Skipping rc.local installation"
        return
    fi

    echo "Configuring /etc/rc.local to run the archive scripts at startup..."
    echo "#!/bin/bash -eu" > ~/rc.local
    echo "archiveserver=\"${archiveserver}\"" >> ~/rc.local
    echo "install_home=\"${install_home}\"" >> ~/rc.local
    cat << 'EOF' >> ~/rc.local
LOGFILE=/tmp/rc.local.log

function log () {
  echo "$( date )" >> "$LOGFILE"
  echo "$1" >> "$LOGFILE"
}

log "Launching archival script..."
"$install_home"/archiveloop "$archiveserver" &
log "All done"
exit 0
EOF

    cat ~/rc.local > /etc/rc.local
    rm ~/rc.local
    echo "Installed rc.local."
}

function check_archive_configs () {
    echo -n "Checking archive configs: "

    case "$ARCHIVE_SYSTEM" in
        rsync)
            check_variable "RSYNC_USER"
            check_variable "RSYNC_SERVER"
            check_variable "RSYNC_PATH"
            export archiveserver="$RSYNC_SERVER"
            ;;
        rclone)
            check_variable "RCLONE_DRIVE"
            check_variable "RCLONE_PATH"
            # FIX: Configurable DNS server instead of hardcoded Google DNS
            export ARCHIVE_DNS_SERVER="${ARCHIVE_DNS_SERVER:-8.8.8.8}"
            export archiveserver="$ARCHIVE_DNS_SERVER"
            ;;
        cifs)
            check_variable "sharename"
            check_variable "shareuser"
            check_variable "sharepassword"
            check_variable "archiveserver"
            ;;
        none)
            ;;
        *)
            echo "STOP: Unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac
    
    echo "done"
}

function get_archive_module () {
    case "$ARCHIVE_SYSTEM" in
        rsync)
            echo "run/rsync_archive"
            ;;
        rclone)
            echo "run/rclone_archive"
            ;;
        cifs)
            echo "run/cifs_archive"
            ;;
        *)
            echo "Internal error: Attempting to configure unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac
}

function install_archive_scripts () {
    local install_path="$1"
    local archive_module="$2"

    echo "Installing base archive scripts into $install_path"
    get_script "$install_path" archiveloop run
    get_script "$install_path" remountfs_rw run
    get_script "$install_path" lookup-ip-address.sh run

    echo "Installing archive module scripts"
    get_script "$install_path" verify-archive-configuration.sh "$archive_module"
    get_script "$install_path" configure-archive.sh "$archive_module"
    get_script "$install_path" archive-clips.sh "$archive_module"
    get_script "$install_path" connect-archive.sh "$archive_module"
    get_script "$install_path" disconnect-archive.sh "$archive_module"
    get_script "$install_path" write-archive-configs-to.sh "$archive_module"
    get_script "$install_path" archive-is-reachable.sh "$archive_module"
}

function check_pushover_configuration () {
    if [ ! -z "${pushover_enabled+x}" ]
    then
        if [ ! -n "${pushover_user_key+x}" ] || [ ! -n "${pushover_app_key+x}"  ]
        then
            echo "STOP: You're trying to setup Pushover but didn't provide your User and/or App key."
            echo "Define the variables like this:"
            echo "export pushover_user_key=put_your_userkey_here"
            echo "export pushover_app_key=put_your_appkey_here"
            exit 1
        elif [ "${pushover_user_key}" = "put_your_userkey_here" ] || [  "${pushover_app_key}" = "put_your_appkey_here" ]
        then
            echo "STOP: You're trying to setup Pushover, but didn't replace the default User and App key values."
            exit 1
        fi
    fi
}

function configure_pushover () {
    if [ ! -z "${pushover_enabled+x}" ]
    then
        echo "Enabling pushover"
        # FIX: Secure credential file permissions
        echo "export pushover_enabled=true" > /root/.teslaCamPushoverCredentials
        echo "export pushover_user_key=$pushover_user_key" >> /root/.teslaCamPushoverCredentials
        echo "export pushover_app_key=$pushover_app_key" >> /root/.teslaCamPushoverCredentials
        chmod 600 /root/.teslaCamPushoverCredentials
    else
        echo "Pushover not configured."
    fi
}

function check_and_configure_pushover () {
    check_pushover_configuration
    configure_pushover
}

function install_pushover_scripts() {
    local install_path="$1"
    get_script "$install_path" send-pushover run
}

if [ "$ARCHIVE_SYSTEM" = "none" ]
then
    echo "Skipping archive configuration."
    exit 0
fi

if ! [ "$(id -u)" = 0 ]
then
    echo "STOP: Run sudo -i."
    exit 1
fi

if [ ! -e "$INSTALL_DIR" ]
then
    mkdir "$INSTALL_DIR"
fi

echo "Getting files from $REPO:$BRANCH"

check_and_configure_pushover
install_pushover_scripts "$INSTALL_DIR"

check_archive_configs

archive_module="$( get_archive_module )"
echo "Using archive module: $archive_module"

install_archive_scripts "$INSTALL_DIR" "$archive_module"
"$INSTALL_DIR"/verify-archive-configuration.sh
"$INSTALL_DIR"/configure-archive.sh

install_rc_local "$INSTALL_DIR"
