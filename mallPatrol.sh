#!/bin/bash
# spell-checker:ignore noout

__Author="Jerren Saunders"
__Version=25.12.10
__ScriptName=$(basename "$0") # File name with extension
__AppDir=$(dirname "$0") # Path where script is stored
__AppName=${__ScriptName%.*} # File name without extension
__origArgs=$* # Capture all of the original arguments


# Default Settings
DEFAULT_FILE="urls.list"

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
#
# Returns: 
# - None
certificate_check() {
    server_name=$2
    warning_age=${3:-30}

    # Adjust padding for indentation
    printf "${CERT_ANSI}"
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$server_name certificate expires: "
    else
        printf "%-55.55s " "$server_name certificate expires: "
    fi
    printf "${ANSI_RST}    "

    response=$(echo | timeout 5 openssl s_client -servername $server_name -connect $server_name:443 2>/dev/null | openssl x509 -noout -enddate)
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
    response=$(echo | ssh -o StrictHostKeyChecking=no $server_name "df -h | awk '{ if (\$5 > $threshold) print \$0 }'" 2>&1)

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

# Main function to iterate through file and call curl on each address
main() {
    # Check if a file name was provided as an alternative list
    if [ $# -eq 0 ]; then
        # No arguments provided, check if a file with the default name exist in the current directory
        if [ -f "${PWD}/${DEFAULT_FILE}" ]; then 
            # Using default file in current directory
            FILE="${PWD}/${DEFAULT_FILE}"

        # Otherwise use the default file in the App Directory
        else
            FILE="${__AppDir}/${DEFAULT_FILE}"
        fi

    # Check if help was requested
    elif [ $# -eq 1 ] && [ "$1" == "-h" ]; then
        echo "Usage: $0 [-h] [filename]"
        exit 0
    elif [ $# -eq 1 ] && [ "$1" == "-v" ]; then
        echo "$__Version"
        exit 0
    elif [ $# -gt 2 ]; then
        echo "Error: Too many arguments provided."
        exit 1
    else
        FILE=$1
    fi

    # If file does not exist, exit
    if [ ! -f "$FILE" ]; then
        echo "Error: File '$FILE' not found."
        exit 1
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
            if [ "$inside_group" = true ]; then
                inside_group=false
                echo ""
            fi

            continue
        fi
        
        # Group Headers - If the line starts with a '['
        if [[ $line =~ ^\[([^\]]*)\]$ ]]; then
            inside_group=true
            echo ""
            echo -e "$GROUP_ANSI${BASH_REMATCH[1]}:$ANSI_RST"
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