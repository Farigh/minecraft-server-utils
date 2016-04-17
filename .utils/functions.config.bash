#! /bin/bash

# in : config_files_dir
# in : default server_data_dir
function load_config_file()
{
    local config_files_dir=$1
    local default_server_data_dir=$2

    if [ ! -d "$config_files_dir" ]; then
        echo "${RED_COLOR}Error: Configuration dir does not exist${RESET_COLOR}"
        exit 1
    fi

    # TODO: handle multiple configurations
    local config_file="${config_dir}/server.cfg"
    if [ ! -f "${config_file}" ]; then
        echo "${RED_COLOR}Error: '${config_file}' config file not found.${RESET_COLOR}"
        exit 1
    fi

    source ${config_file}

    if [ "$server_data_dir" == "" ]; then
        server_data_dir="$default_server_data_dir"
        echo "${CYAN_COLOR}server_data_dir is not set in config file, falling back to default ($server_data_dir)${RESET_COLOR}"
    fi

    if [ ! -d "$server_data_dir" ]; then
        if [ -e "$server_data_dir" ]; then
            echo "${RED_COLOR}Error: '$server_data_dir' exists but is not a directory${RESET_COLOR}"
            exit 1
        fi
    fi
}