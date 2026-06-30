#!/bin/bash
# spell-checker:ignore noout

__Author="Jerren Saunders"
__Version=26.6.30
__ScriptName=$(basename "$0") # File name with extension
__AppDir=$(dirname "$0") # Path where script is stored
__AppName=${__ScriptName%.*} # File name without extension
__origArgs=$* # Capture all of the original arguments


# Default Settings
DEFAULT_FILE="urls.list"
WAIT_MODE=false

GROUP_ANSI="\e[0;4;34m"
PING_ANSI="\e[0;37m"
CURL_ANSI="\e[0;37m"
CERT_ANSI="\e[0;37m"
PORT_ANSI="\e[0;37m"
UP_ANSI="\e[0;37m"
DISK_ANSI="\e[0;37m"
NOTE_ANSI="\e[2;3;32m"
EXPECT_ANSI="\e[1;35m"
ANSI_RST="\e[0m"

ERROR_HEADER_ANSI="\e[1;4;31m"
ERROR_ANSI="\e[0;1;31m"

# PASS_ANSI="\e[32m"
PASS_ANSI="\e[38;5;46m"
FAIL_ANSI="\e[1;31m"

PASS_MARK="$PASS_ANSI\u2713$ANSI_RST"
FAIL_MARK="$FAIL_ANSI\u2717$ANSI_RST"

function printUsage() {
    includeAppInfo=${1}
    cat <<EOT

This script will perform health checks on a list of URLs and services defined in a text file.
The default file name is 'urls.list', but a different file can be specified as an argument.

Syntax:
    ${__ScriptName} [-g groupname] [-f filename] [-w target] [-l] [-v] [-h] [filename|groupname] 
    -g groupname   Only process entries within the specified group
    -f filename    Specify an alternate file containing the list of URLs and services to check
    -w target      Wait for ping success for an IP, hostname, or group name
    -l             List available group names in the selected list file and exit
    -v             Display the script version and exit
    -h             Display this help message and exit

List File:
    The list file (default is 'urls.list') supports the following syntax:
    
    <ip|fqdn>                    - Ping the specified host or IP address
    <http <url>|https <url>>     - Perform an HTTP GET request to the specified URL
    <[Group Name]>               - Define a group header for organizing entries
    <cert <server> [age] [port]> - Check the SSL certificate expiration date for the specified server
                                   The optional 'age' parameter specifies the warning threshold in days (default is 30)
                                   The optional 'port' parameter specifies the TLS port to check (default is 443)
    <port <server> <port>>       - Check if the specified port is open on
    <up <server>>                - Check the uptime of the specified server via SSH (should use SSH for auth)
    <note <msg>>                 - Print a note message in the output
    <disk <server> [thresh]>     - Check disk usage on the specified server via SSH
                                   The optional 'thresh' parameter specifies the Use% threshold (default is 80)

Wait Mode:
    Use '-w target' to ping once per second until host responds.
    If target matches a group name, only pingable entries are considered from the list file for that group.
    The mode requires exactly one pingable host for a matched group.
    If multiple are defined, you will need to explicitly provide the target server or IP with '-w <target>'.
    Press 'q' to abort. On success, the terminal bell rings 3 times.
EOT

    if [[ ${includeAppInfo} ]]; then 
        cat <<EOT
Version: ${__Version}
EOT
    fi
}

##
# Sends a GET request to a given URL using curl and checks the HTTP response code.
#
# Parameters:
# - url: The URL to send the GET request to.
# - expected_status_code (optional): The expected HTTP response code. Defaults to 200.
#
# Returns:
# - None.
call_curl() {
    url=$1
    expected_status_code=${2:-200}

    # Adjust padding for indentation
    printf "${CURL_ANSI}"
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$url"
    else
        printf "%-55.55s " "$url"
    fi
    printf "${ANSI_RST}"

    response=$(curl --connect-timeout 10 --silent --location --output /dev/null --write-out "%{http_code}" "$url")
    printf "${EXPECT_ANSI}%3d${ANSI_RST} " "$response"
    if [ "$response" -ne "$expected_status_code" ]; then
        printf "$FAIL_MARK (Expected %s)" "$expected_status_code"
        errors+=("   Unexpected status code: $response (Expected $expected_status_code) - URL: $url")
    else
        printf "$PASS_MARK"
    fi
    printf '\n'
}

##
# Checks the certificate end date of the given URL
#
# Parameters:
# - server: The server name to retrive the certificate for
# - warning_age (optional): The age at which a warning should be raised. Defaults to 30.
# - cert_port (optional): The TLS port to query. Defaults to 443.
#
# Returns:
# - None
certificate_check() {
    server_name=$2
    warning_age=${3:-30}
    cert_port=${4:-443}

    # Adjust padding for indentation
    printf "${CERT_ANSI}"
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$server_name certificate expires: "
    else
        printf "%-55.55s " "$server_name certificate expires: "
    fi
    printf "${ANSI_RST}    "

    response=$(echo | timeout 5 openssl s_client -servername "$server_name" -connect "$server_name:$cert_port" 2>/dev/null | openssl x509 -noout -enddate)
    # response = "notAfter=Feb 27 20:26:32 2028 GMT"

    # Extract the date string from 'notAfter='
    enddate_val=${response#notAfter=}

    # Convert end date to seconds since epoch
    end_seconds=$(date -d "$enddate_val" +%s)
    now_seconds=$(date +%s)

    # Calculate days remaining
    days_left=$(( (end_seconds - now_seconds) / 86400 ))

    if [ "$days_left" -le "$warning_age" ]; then
        printf "$FAIL_MARK"
        errors+=("   Certificate for $server_name expires in $days_left days")
    else
        printf "$PASS_MARK"
    fi
    printf "  ${EXPECT_ANSI}%s (%s days)${ANSI_RST}" "$enddate_val" "$days_left"
    printf '\n'
}

##
# Checks if the given port is open on the specificed host
#
# Parameters:
# - server: The server name to check
# - port: The port number to check
#
# Returns:
# - None
port_probe() {
    server_name=$2
    port_num=$3

     # Adjust padding for indentation
    lbl="Port $port_num ($server_name)"
    printf "${PORT_ANSI}"
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$lbl"
    else
        printf "%-55.55s " "$lbl"
    fi
    printf "${ANSI_RST}    "

    # nc -z localhost $1 && echo "port open" || echo "port closed"
    if nc -z $server_name $port_num; then
        printf "$PASS_MARK"
    else
        printf "$FAIL_MARK"
        errors+=("   Port $port_num on $server_name is closed")
    fi
    printf '\n'
}

##
# Gets the uptime of the given server
#
# Parameters:
# - server: The server name to check
#
# Returns:
# - None
get_uptime() {
    server_name=$2

     # Adjust padding for indentation
    lbl="Uptime ($server_name)"
    printf "${UP_ANSI}"
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$lbl"
    else
        printf "%-55.55s " "$lbl"
    fi
    printf "${ANSI_RST}    "

    # # From https://stackoverflow.com/a/59592881/2136313
    # {
    #     local IFS=$'\n';
    #     read -r -d '' CAPTURED_STDERR;
    #     local IFS=$'\n';
    #     read -r -d '' CAPTURED_STDOUT;
    # } < <((printf '\0%s\0' "$(ssh -o StrictHostKeyChecking=no $server_name "uptime -p")" 1>&2) 2>&1)
    response=$(echo | ssh -o StrictHostKeyChecking=no $server_name "uptime -p" 2>&1)

    # If nothing was captured by stderr, assume success
    if [ $? -eq 0 ]; then
        printf "$PASS_MARK"
        printf "  ${EXPECT_ANSI}%s${ANSI_RST}" "$response"
    else
        printf "$FAIL_MARK"
        errors+=("   $response")
    fi

    printf '\n'
}

##
# Checks the disk usage on the given server to see if any mount points exceed the specificed Use% threshold
#
# Parameters:
# - server: The server name to check
# - threshold (optional): The Use% threshold to check against. Defaults to '80'.
#
# Returns:
# - None
get_diskusage() {
    server_name=$2
    threshold=${3:-80} # Default threshold is 80%

     # Adjust padding for indentation
    lbl="Disk Usage ($server_name)"
    printf "${DISK_ANSI}"
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$lbl"
    else
        printf "%-55.55s " "$lbl"
    fi
    printf "${ANSI_RST}    "
    response=$(echo | ssh -o StrictHostKeyChecking=no $server_name "df -h | awk '{ if (NR == 1 || \$5+0 > $threshold) print \$0 }'" 2>&1)

    # If only one line was captured (header), assume success
    if [ $(echo "$response" | wc -l) -eq 1 ]; then
        printf "$PASS_MARK"
    else
        printf "$FAIL_MARK"
        errors+=("Limited Disk Space on $server_name:")

        # Split the response into separate lines and add them to the errors array with indentation
        while IFS= read -r line; do
            indented_line="    $line"
            errors+=("$indented_line")
        done <<< "$response"
    fi

    printf '\n'
}

##
# Pings the given target host or IP address and prints the status.
#
# Parameters:
# - tgt: The target host or IP address.
#
# Returns:
# - None.
call_ping() {
    tgt=$1

    # Adjust padding for indentation
    printf "${PING_ANSI}"
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$tgt"
    else
        printf "%-55.55s " "$tgt"
    fi
    printf "${ANSI_RST}    "

    ping -c 1 -w 1 "$tgt" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        printf "$FAIL_MARK"
        errors+=("   Host unreachable: $tgt")
    else
        printf "$PASS_MARK"
    fi
    printf '\n'
}

is_pingable_entry() {
    entry="$1"

    if [ -z "$entry" ] || [[ $entry =~ ^# ]]; then
        return 1
    fi

    if [[ $entry =~ ^(http|https|cert|port|up|disk|note)([[:space:]]|$) ]]; then
        return 1
    fi

    return 0
}

ring_success_bell() {
    for i in 1 2 3; do
        if command -v tput > /dev/null 2>&1; then
            tput bel
        else
            printf '\a'
        fi

        if [ "$i" -lt 3 ]; then
            sleep 1.25
        fi
    done
}

resolve_wait_target() {
    requested_target="$1"
    matched_group=false
    in_matched_group=false
    ip_targets=()
    host_targets=()

    while IFS= read -r line; do
        # Group header
        if [[ $line =~ ^\[([^\]]*)\]$ ]]; then
            current_group="${BASH_REMATCH[1]}"
            if [ "$current_group" = "$requested_target" ]; then
                matched_group=true
                in_matched_group=true
            else
                in_matched_group=false
            fi
            continue
        fi

        # End group on blank line
        if [ -z "$line" ]; then
            in_matched_group=false
            continue
        fi

        # Only consider lines in matched group
        if [ "$in_matched_group" = true ]; then
            # Skip comments, directives, and lines with spaces
            if [[ $line =~ ^# ]] || [[ $line =~ ^(http|https|cert|port|up|disk|note)([[:space:]]|$) ]] || [[ "$line" =~ " " ]]; then
                continue
            fi

            # IP address regex (IPv4 only)
            if [[ $line =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                ip_targets+=("$line")
            # Hostname (FQDN, not IP, no spaces)
            elif [[ $line =~ ^[A-Za-z0-9.-]+$ ]]; then
                host_targets+=("$line")
            fi
        fi
    done < "$FILE"

    if [ "$matched_group" = true ]; then
        ip_count=${#ip_targets[@]}
        host_count=${#host_targets[@]}

        # No valid targets
        if [ "$ip_count" -eq 0 ] && [ "$host_count" -eq 0 ]; then
            echo "Error: Group '$requested_target' has no pingable host or IP entries."
            return 2
        fi

        # If exactly 1 IP, use it
        if [ "$ip_count" -eq 1 ] && [ "$host_count" -eq 0 ]; then
            WAIT_RESOLVED_TARGET="${ip_targets[0]}"
            return 0
        fi
        # If exactly 1 hostname, use it
        if [ "$ip_count" -eq 0 ] && [ "$host_count" -eq 1 ]; then
            WAIT_RESOLVED_TARGET="${host_targets[0]}"
            return 0
        fi
        # If exactly 1 IP and 1 hostname, assume same, use IP
        if [ "$ip_count" -eq 1 ] && [ "$host_count" -eq 1 ]; then
            WAIT_RESOLVED_TARGET="${ip_targets[0]}"
            return 0
        fi
        # If >1 IP or >1 hostname, error
        echo "Error: Group '$requested_target' has too many pingable targets (IPs: $ip_count, hosts: $host_count)."
        if [ "$ip_count" -gt 0 ]; then
            echo "  IPs:"
            for ip in "${ip_targets[@]}"; do
                echo "    $ip"
            done
        fi
        if [ "$host_count" -gt 0 ]; then
            echo "  Hostnames:"
            for host in "${host_targets[@]}"; do
                echo "    $host"
            done
        fi
        echo ""
        echo "Use '-w <host>' with one explicit host or IP."
        echo ""
        return 2
    fi

    WAIT_RESOLVED_TARGET="$requested_target"
    return 0
}

wait_for_ping_response() {
    requested_target="$1"
    ping_count=0

    resolve_wait_target "$requested_target"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        return "$rc"
    fi

    echo -e "${EXPECT_ANSI}Waiting for ping response from: ${WAIT_RESOLVED_TARGET}${ANSI_RST}"
    echo "Press 'q' to abort."

    # Disable terminal echo to absorb 'q' keypress
    stty -echo

    trap 'stty echo' EXIT  # Ensure echo is restored on exit

    while true; do
        if read -r -t 0.01 -n 1 -s key && [ "$key" = "q" ]; then
            printf "\nAborted.\n"
            stty echo  # Restore echo before exiting
            return 1
        fi

        ping_count=$((ping_count + 1))
        printf "\r${PING_ANSI}Target: %s | Ping attempts: %d${ANSI_RST}" "$WAIT_RESOLVED_TARGET" "$ping_count"

        if ping -W1 -c1 "$WAIT_RESOLVED_TARGET" > /dev/null 2>&1; then
            printf "\n$PASS_MARK Host responded after %d attempt(s).\n" "$ping_count"
            ring_success_bell
            return 0
        fi
    done

    # Restore terminal echo explicitly in case of normal exit
    stty echo
}

##
# Handles command line arguments and sets global variables accordingly
#
# Parameters:
# - Always pass $@
#
process_cl_args() {
    while getopts ":hlvf:g:w:" opt; do
        case $opt in
            h)
                printUsage true
                exit 0
                ;;
            l)
                LIST_GROUPS=true
                ;;
            v)
                echo "$__Version"
                exit 0
                ;;
            f)
                FILE=$OPTARG
                ;;
            g)
                GROUP_NAME=$OPTARG
                ;;
            w)
                WAIT_MODE=true
                WAIT_TARGET=$OPTARG
                ;;
            \?)
                echo "Error: Invalid option -$OPTARG" >&2
                echo "   Use '${__ScriptName} -h' to view usage information"
                exit 1
                ;;
            :)
                echo "Error: Option -$OPTARG requires an argument." >&2
                echo "   Use '${__ScriptName} -h' to view usage information"
                exit 1
                ;;
        esac
    done

    # Shift off the options and optional --
    shift $((OPTIND -1))

    if [ "$WAIT_MODE" = true ] && [ "$LIST_GROUPS" = true ]; then
        echo "Error: Options '-w' and '-l' cannot be used together."
        exit 1
    fi

    if [ "$WAIT_MODE" = true ] && [ -n "$GROUP_NAME" ]; then
        echo "Error: Option '-g' cannot be used with '-w'."
        exit 1
    fi

    if [ "$WAIT_MODE" = true ] && [ $# -gt 0 ]; then
        echo "Error: Positional arguments are not supported with '-w'."
        echo "   Use '-w <target>' and optional '-f <filename>'."
        exit 1
    fi

    # Remaining arguments are either file or group name
    if [ "$WAIT_MODE" != true ] && [ $# -gt 1 ]; then
        echo "Error: Too many arguments provided."
        echo "   Use '${__ScriptName} -h' to view usage information"
        exit 1    
    elif [ "$WAIT_MODE" != true ] && [ $# -eq 1 ]; then
        # Single argument provided, check if it is a file, otherwise treat as a group name
        if [ -f "$1" ]; then 
            FILE=$1
        else
            GROUP_NAME=$1
        fi
    fi

    # Handle FILE path if not yet set
    if [ -z "$FILE" ]; then
        # No arguments provided, check if a file with the default name exist in the current directory
        if [ -f "${PWD}/${DEFAULT_FILE}" ]; then
            # Using default file in current directory
            FILE="${PWD}/${DEFAULT_FILE}"

        # Otherwise use the default file in the App Directory
        else
            FILE="${__AppDir}/${DEFAULT_FILE}"
        fi
    fi

    # If file does not exist, exit
    if [ ! -f "$FILE" ]; then
        echo "Error: File '$FILE' not found."
        exit 1
    fi
}

##
# Scans the selected list file and prints detected unique group names.
#
# Parameters:
# - None (uses global FILE)
#
# Returns:
# - None.
list_group_names() {
    declare -A seen_groups=()

    while IFS= read -r line; do
        # Ignore comments and empty lines
        if [[ $line =~ ^# ]] || [ -z "$line" ]; then
            continue
        fi

        if [[ $line =~ ^\[([^\]]*)\]$ ]]; then
            current_group="${BASH_REMATCH[1]}"

            # Skip blank group names and duplicates
            if [ -n "$current_group" ] && [ -z "${seen_groups[$current_group]}" ]; then
                seen_groups["$current_group"]=1
                echo "  $current_group"
            fi
        fi
    done < "$FILE"
}


# Main function to iterate through file and call curl on each address
main() {
    process_cl_args "$@"

    if [ "$WAIT_MODE" = true ]; then
        wait_for_ping_response "$WAIT_TARGET"
        exit $?
    fi

    if [ "$LIST_GROUPS" = true ]; then
        list_group_names
        exit 0
    fi

    # Print header
    printf "%-55s %s\n" "URL" "Response"
    echo "----------------------------------------------------------------------"

    # Now, loop through each line in the file and perform the desired action
    while IFS= read -r line; do
        # Ignore comments
        if [[ $line =~ ^# ]]; then
            continue
        fi

        # Ignore empty lines (reset if in a group)
        if [ -z "$line" ]; then
            # If inside a group, add an empty line
            if [ "$inside_group" = true ] && [ -z "$GROUP_NAME" ]; then
                inside_group=false
                echo ""
            fi
            continue
        fi

        # Group Headers - If the line starts with a '['
        if [[ $line =~ ^\[([^\]]*)\]$ ]]; then
            inside_group=true
            current_group="${BASH_REMATCH[1]}"

            # Skip printing the group header if a specific group name was specified
            if [ -n "$GROUP_NAME" ]; then
                continue
            fi

            # Print the group header
            echo ""
            echo -e "$GROUP_ANSI${current_group}:$ANSI_RST"
            continue
        fi

        # If a group name was specified, and we are not inside that group, skip the entry
        if [ -n "$GROUP_NAME" ] && [ "$GROUP_NAME" != "$current_group" ]; then
            continue
        fi        

        # If inside a group, indent the result output
        printf "%s" "${inside_group:+  }"

        # HTTP(S) - Call curl on the URL, with optional expected status code
        if [[ $line =~ ^http ]]; then
            call_curl $line

        # Certificate Check
        elif [[ $line =~ ^cert ]]; then
            certificate_check $line

        # Port Probe
        elif [[ $line =~ ^port ]]; then
            port_probe $line

        # Up Time
        elif [[ $line =~ ^up ]]; then
            get_uptime $line

        # Disk Usage
        elif [[ $line =~ ^disk ]]; then
            get_diskusage $line

        elif [[ $line =~ ^note ]]; then
            echo -e "$NOTE_ANSI# ${line#* }$ANSI_RST"

        # Otherwise, assume the line is a hostname or IP and ping it
        else
            call_ping $line
        fi
    done < "$FILE"
    printf "\n\n"

    # Report errors if any were found
    if [ "${#errors[@]}" -gt 0 ]; then
        echo -e "${ERROR_HEADER_ANSI}Errors:${ERROR_ANSI}"
        for err in "${errors[@]}"; do
            echo -e "$err"
        done
        echo -e $ANSI_RST
        exit "${#errors[@]}"
    fi

    exit 0
}

main "$@"