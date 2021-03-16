#! /bin/bash

resolved_script_path=$(readlink -f "$0")
current_script_dir=$(dirname "${resolved_script_path}")
current_full_path=$(readlink -e "${current_script_dir}")

# Includes
utils_dir="${current_full_path}/.utils"

source "${utils_dir}/functions.config.bash"
source "${utils_dir}/vars.colors.bash"
source "${utils_dir}/vars.default.bash"

# in : history position to get (backward; forward)
function get_history()
{
    local operation_type=$1
    local new_history_index=$buffer_history_current_index

    # No history yet
    if [ $new_history_index -eq 0 ]; then
        return
    fi

    # Compute history content index
    if [ "${operation_type}" == "backward" ]; then
        ((new_history_index--))

        # Detect out-of-range
        if [ $new_history_index -lt $buffer_history_min_index ]; then
            return
        fi

        # Save current buffer the 1st time we go backward
        if [ $buffer_history_current_index -gt $buffer_history_max_index ]; then
            staged_buffer=$input_buffer
        fi
    else # forward
        ((new_history_index++))

        # Detect out-of-range (if staged buffer, restore it)
        if [ $new_history_index -gt $buffer_history_max_index ] && [ "${staged_buffer}" == "" ]; then
            return
        fi
    fi

    buffer_history_current_index=$new_history_index

    # Erase on-screen buffer display before displaying new buffer content
    erase_buffer_content

    # Update buffer
    if [ $buffer_history_current_index -gt $buffer_history_max_index ]; then
        input_buffer=$staged_buffer
        staged_buffer=""
    else
        input_buffer=${buffer_history[$buffer_history_current_index]}
    fi

    # Restore promp
    restore_promp
}

function erase_buffer_content()
{
    local current_term_cols=$(tput cols)
    local buffer_line_occupation=$(((${#input_buffer} + ${#prompt_value}) / $current_term_cols))
    # +1 for input separator line
    ((buffer_line_occupation++))

    # Erase current line (before pointer)
    tput el1
    # Move cursor back to the beginning of the line
    echo -ne "\r"

    # Move cursor up as many times as needed
    for ((line_count=0; line_count < $buffer_line_occupation; line_count++)); do
        tput cuu1
    done

    # Clear term until end of screen
    tput ed
}

function restore_promp()
{
    # Add input separator line
    # TODO: fit screen size ?
    echo "=============== (enter 'q' to quit) ==============="

    # Restore input buffer
    echo -n "${prompt_value}${input_buffer}"
}

function process_logs()
{
    local index=0
    local linebuffer

    # If no new entry in logs, just return
    if [ $(($backlog_start - 1)) -eq $(wc -l "${server_latest_logs}" | cut -d' ' -f1) ]; then
        return
    fi

    while read -e log_line; do
        linebuffer[$index]=$log_line
        ((index++))
    done < <(tail -n+$backlog_start "${server_latest_logs}")

    #######################
    ### Refresh display ###
    #######################

    # Erase command part
    erase_buffer_content

    # Print all buffered lines
    for ((line_index=0; line_index < index; line_index++)); do
        echo "${linebuffer[$line_index]}"
        ((backlog_start++))
    done

    restore_promp
}

function wait_for_server_logs()
{
    declare -A wait_animated_steps
    wait_animated_steps[0]="|"
    wait_animated_steps[1]="/"
    wait_animated_steps[2]="-"
    wait_animated_steps[3]="\\"
    local wait_animated_steps_index=0
    local erase_current_line_sequence="\r$(tput el)" # clear to end of line

    while [ ! -e "${minecraft_server_stdin}" ]; do
        echo -en "${erase_current_line_sequence}Waiting for the process to start... ${wait_animated_steps[$wait_animated_steps_index]}"
        wait_animated_steps_index=$(((wait_animated_steps_index + 1) % 4))
        sleep 0.5;
    done
    echo -e "${erase_current_line_sequence}Waiting for the process to start...Done"
}

################################################
###                   MAIN                   ###
################################################

config_dir="${current_full_path}/config"

load_config_file $config_dir $default_server_data_dir

minecraft_server_stdin="${server_data_dir}/minecraft_server.stdin"
server_latest_logs="${server_data_dir}/logs/latest.log"

# Wait for server to start logging
wait_for_server_logs

max_backlog_size=10
backlog_start=$(($(wc -l "${server_latest_logs}" | cut -d' ' -f1) - $max_backlog_size))
if [ $backlog_start -lt 1 ]; then
    backlog_start=1
fi

declare -A buffer_history
max_buffer_history_entry=20
buffer_history_min_index=1
buffer_history_current_index=0
staged_buffer=""
buffer_history_max_index=0
prompt_value=" > "
input_buffer=""

# Initialise backlog buffer
process_logs

# Read timeout set to 1 for backlog refresh
while true; do
    IFS= read -t1 -r -s -n1 char
    read_status=$?

    case "${char}" in
        # Carriage return (read_status != 0 means we timed out)
        $'\0')
            if [ $read_status -eq 0 ]; then
                if [ "${input_buffer}" == "q" ]; then
                    break
                fi
                # Erase on-screen buffer display before sending content
                erase_buffer_content
                echo "${input_buffer}" > $minecraft_server_stdin;

                # Restore promp
                restore_promp

                # Add entry to history (do not record empty cmd)
                if [ "${input_buffer}" != "" ]; then
                    ((buffer_history_max_index++))
                    buffer_history[$buffer_history_max_index]=$input_buffer
                    buffer_history_current_index=$(($buffer_history_max_index + 1))

                    # Purge history
                    if [[ $(($buffer_history_max_index - $buffer_history_min_index)) -ge $max_buffer_history_entry ]]; then
                        unset buffer_history[$buffer_history_min_index]
                        ((buffer_history_min_index++))
                    fi
                fi

                # Reset buffer
                input_buffer=""
                staged_buffer=""

                # Wait 50ms for logs to refresh so command result appears right away
                sleep 0.05
            fi
        ;;
        $'\177')
            # Backspace char
            if [ ${#input_buffer} -gt 0 ]; then
                input_buffer=${input_buffer::-1}
                # Erase char on screen
                tput cub 1
                echo -n " "
                tput cub 1
            fi
        ;;
        $'\e')
            # Escape sequence, skip next 2 chars (most common escape sequence, should read 1 or 2 more for all special keys)
            read -s -n1 -t 0.0001 skip1
            read -s -n1 -t 0.0001 skip2

            # Look for some special keys
            if [ "${skip1}" == "[" ] || [ "$skip1" == "0" ]; then
                case "${skip2}" in
                    # Up key
                    'A')
                        get_history backward
                    ;;
                    # Down key
                    'B')
                        get_history forward
                    ;;
                esac
            fi
        ;;
        $'\t')
            # Ignore tabs
        ;;
        # Any other char
        *)
            input_buffer="${input_buffer}${char}"

            # Any modification to the current line must reset buffer_history_current_index
            buffer_history_current_index=$(($buffer_history_max_index + 1))

            # Display char
            echo -n "${char}"
        ;;
    esac

    process_logs
done

erase_buffer_content
echo -e "Exited"
