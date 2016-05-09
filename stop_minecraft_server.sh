#! /bin/bash

resolved_script_path=`readlink -f $0`
current_script_dir=`dirname $resolved_script_path`
current_full_path=`readlink -e $current_script_dir`

# Includes
utils_dir="$current_full_path/.utils"

source "$utils_dir/functions.config.bash"
source "$utils_dir/vars.colors.bash"
source "$utils_dir/vars.default.bash"

# in : minecraft server data dir
# in : time to shutdown
function send_and_log_time_to_shutdown()
{
    local minecraft_server_data_dir="$1"
    local time_to_shutdown="$2"
    local message_time=$(date +"%H:%M:%S")

    local minecraft_server_stdin="$minecraft_server_data_dir/minecraft_server.stdin"
    local minecraft_server_log="$minecraft_server_data_dir/logs/latest.log"

    local text_to_display
    if [ "$time_to_shutdown" != "now" ]; then
        text_to_display="Server will automatically shutdown in $time_to_shutdown"
    else
        text_to_display="Stopping server"
    fi

    echo "tellraw @a {\"text\":\"$text_to_display\",color:\"dark_red\"}" >> "$minecraft_server_stdin"
    echo "[$message_time] [Server] $text_to_display" | tee -a "$minecraft_server_log"

    if [ "$time_to_shutdown" == "now" ]; then
        echo "stop" >> "$minecraft_server_stdin"
    fi
}

timer_index=0
declare -A timer_text_array
declare -A timer_sleep_time_array

# in : timer text
# in : time to next message
function timer_values_add()
{
    timer_text_array[$timer_index]=$1
    timer_sleep_time_array[$timer_index]=$2

    ((timer_index++))
}

################################################
###                   MAIN                   ###
################################################

config_dir="${current_full_path}/config"

load_config_file $config_dir $default_server_data_dir

if [ ! -p "$server_data_dir/minecraft_server.stdin" ]; then
    echo "${RED_COLOR}Error: can't find server fifo, make sure the server is running${RESET_COLOR}"
    exit 1
fi

# -n option shuts down in only 30 seconds
if [ "$1" != "-n" ]; then
    timer_values_add "10 minutes" $((5 * 60))
    timer_values_add "5 minutes" $((4 * 60))
    timer_values_add "1 minute" 30
fi

timer_values_add "30 seconds" 20
timer_values_add "10 seconds" 10
timer_values_add "now" 0

for ((index=0; index <= $(($timer_index - 1)); index++)); do
    send_and_log_time_to_shutdown $server_data_dir "${timer_text_array[$index]}"

    time_to_sleep=${timer_sleep_time_array[$index]}
    if [ $time_to_sleep -gt 0 ]; then
        sleep $time_to_sleep
    fi
done

declare -A server_stop_animated_steps
server_stop_animated_steps[0]="|"
server_stop_animated_steps[1]="/"
server_stop_animated_steps[2]="-"
server_stop_animated_steps[3]="\\"
server_stop_animated_steps_index=0
erase_current_line_sequence="\r$(tput el)" # clear to end of line
timeout=120 # Server should stop in less than 2 minutes
while [ "$(docker inspect -f {{.State.Running}} $docker_name)" == "true" ]; do
    echo -ne "${erase_current_line_sequence}Waiting for docker container to stop... ${server_stop_animated_steps[$server_stop_animated_steps_index]}"
    server_stop_animated_steps_index=$(((server_stop_animated_steps_index + 1) % 4))
    ((timeout--))
    if [ $timeout -eq 0 ]; then
        echo "${RED_COLOR}Error: docker container is hanging, calling stop${RESET_COLOR}"
        docker stop $docker_name
    fi
    sleep 1
done

echo -e "${erase_current_line_sequence}Waiting for docker container to stop...Done"
