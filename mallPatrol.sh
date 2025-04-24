#!/bin/bash

__Author="Jerren Saunders"
__Version=25.4.24
__ScriptName=$(basename "$0") # File name with extension
__AppDir=$(dirname "$0") # Path where script is stored
__AppName=${__ScriptName%.*} # File name without extension
__origArgs=$* # Capture all of the original arguments


# Default Settings
DEFAULT_FILE="urls.list"

# Function to call curl and send wall message on failure
call_curl() {
    url=$1
    expected_status_code=${2:-200}
    
    printf "%-55s " "$url"
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

# Main function to iterate through file and call curl on each address
main() {
    if [ $# -eq 0 ]; then
        # No arguments provided, use default file name in PWD or App Directory
        if [ -f "${PWD}/${DEFAULT_FILE}" ]; then 
            FILE="${PWD}/${DEFAULT_FILE}"
        else
            FILE="${__AppDir}/${DEFAULT_FILE}"
        fi
    elif [ $# -eq 1 ] && [ "$1" == "-h" ]; then
        echo "Usage: $0 [-h] [filename]"
        exit 0
    elif [ $# -gt 2 ]; then
        echo "Error: Too many arguments provided."
        exit 1
    else
        FILE=$1
    fi

    if [ ! -f "$FILE" ]; then
        # If file does not exist, try to use default file name in PWD
        echo "Error: File '$FILE' not found."
        exit 1
    fi

    printf "%-55s %s\n" "URL" "Response"
    echo "----------------------------------------------------------------------"

    while IFS= read -r line; do
        # Ignore comments and empty lines
        if [[ $line =~ ^# ]] || [ -z "$line" ]; then
            continue
        fi
        
        # Call curl on the URL, with optional expected status code
        call_curl $line        
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