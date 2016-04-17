#! /bin/bash

resolved_script_path=`readlink -f $0`
current_script_dir=`dirname $resolved_script_path`
current_full_path=`readlink -e $current_script_dir`
default_server_data_dir="$current_full_path/server_data"

# Includes
utils_dir="$current_full_path/.utils"

source "$utils_dir/functions.config.bash"
source "$utils_dir/vars.colors.bash"

################################################
###                   MAIN                   ###
################################################

config_dir="${current_full_path}/config"

load_config_file $config_dir $default_server_data_dir

minecraft_server_stdin="$server_data_dir/minecraft_server.stdin"

while [ ! -e "$minecraft_server_stdin" ]; do
    echo "Waiting for the process to launch $minecraft_server_stdin"
    sleep 1;
done

tail -f $server_data_dir/logs/latest.log &
output_reader_pid=$!
echo "PID = $output_reader_pid"

function kill_processes()
{
    echo "Quit"
    kill -9 $output_reader_pid
    exit 0
}

trap "kill_processes" SIGHUP SIGINT SIGTERM SIGKILL

while read line; do
    if [ "$line" == "q" ]; then
        break
    fi
    echo $line > $minecraft_server_stdin;
done


kill_processes
