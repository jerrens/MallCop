#!/bin/bash

__Author="Jerren Saunders"
__Version=25.5.15
__ScriptName=$(basename "$0") # File name with extension
__AppDir=$(dirname "$0") # Path where script is stored
__AppName=${__ScriptName%.*} # File name without extension
__origArgs=$* # Capture all of the original arguments


# Default Settings
DEFAULT_FILE="urls.list"

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
    if [ "$inside_group" = true ]; then
        printf "%-53.53s " "$url"
    else
        printf "%-55.55s " "$url"
    fi

    response=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    printf "%3d " "$response"
    if [ "$response" -ne "$expected_status_code" ]; then
        printf "\u2717 (Expected %s)" "$expected_status_code"
        errors+=("   Unexpected status code: $response (Expected $expected_status_code) - URL: $url")
    else
        printf '\u2713'
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

    printf "%-57.55s " "$tgt"
    
    ping -c 1 "$tgt" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        printf "\u2717"
        errors+=("   Host unreachable: $tgt")
    else
        printf '\u2713'
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
            echo "${BASH_REMATCH[1]}:"
            continue
        fi
        
        # If inside a group, indent the result output
        printf "%s" "${inside_group:+  }"
        
        # HTTP(S) - Call curl on the URL, with optional expected status code
        if [[ $line =~ ^http ]]; then
            call_curl $line                
        
        # Otherwise, assume the line is a hostname or IP and ping it
        else
            call_ping $line
        fi

    done < "$FILE"
    printf "\n\n"

    # Report errors if any were found
    if [ "${#errors[@]}" -gt 0 ]; then
        echo "Errors:"
        for err in "${errors[@]}"; do
            echo "$err"
        done
        exit "${#errors[@]}"
    fi

    exit 0
}

main "$@"