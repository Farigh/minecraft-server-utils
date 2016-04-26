#! /bin/bash

function generate_default_config_file()
{
    local config_files_path=$1
    local error_prefix="Config file generation error"

    # Detect directory (basename strips the final /)
    if [[ "$config_files_path" == *"/" ]]; then
        echo "${RED_COLOR}${error_prefix}: Directory provided: '$config_files_path'${RESET_COLOR}"
        exit 1
    fi

    local config_files_basename=$(basename $config_files_path)
    local config_files_dirname="$(dirname $config_files_path)/"

    # Prepend .cfg extension if not present
    if [[ "$config_files_basename" != *".cfg" ]]; then
        config_files_basename="${config_files_basename}.cfg"
    fi

    local config_files_fullpath="${config_files_dirname}${config_files_basename}"

    if [ -e "$config_files_fullpath" ]; then
        echo "${RED_COLOR}${error_prefix}: File already exists: '$config_files_fullpath'${RESET_COLOR}"
        exit 1
    fi

    # Create dir if needed
    if [ ! -d "$config_files_dirname" ]; then
        if [ -e "$config_files_dirname" ]; then
            echo "${RED_COLOR}${error_prefix}: '$config_files_dirname' exists but is not a directory${RESET_COLOR}"
            exit 1
        else
            mkdir "$config_files_dirname" || \
                (echo "${RED_COLOR}${error_prefix}: Can't create configuration dir : '$config_files_dirname'${RESET_COLOR}" \
                 && exit 1)
        fi
    fi

    touch "${config_files_fullpath}" || \
        (echo "${RED_COLOR}${error_prefix}: Can't create configuration file : '$config_files_fullpath'${RESET_COLOR}" \
         && exit 1)

    echo "# Server deployment configuration file

# Docker container base update checking
# Switch to 'true' to check for docker file updates
docker_check_for_updates=false

# Docker linux distribution auto-update
# Switch to 'true' to updates Linux paquages on start
linux_autoupdate=false

# Docker container name (change it if you plan on running multiple configurations)
docker_name=minecraft_server

# Docker container version (change it at your own risk)
docker_commit=c362e5bdd80a84ecb601d3dabd6ea49d74b19039d6dee665b1bdd90538b6506b

# Docker data dir location (this can not be empty, default is <start_script_dir>/server_data)
# Uncomment it to change this value (if dir does not exist it will be created)
# server_data_dir=

# Minecraft server port (default port is 25565)
minecraft_host_port=25565

# Minecraft version (enter a specific number if you want a fixed version)
# Special values :
#    LATEST
#    SNAPSHOT
minecraft_version=LATEST

# Minecraft server type
# Available values :
#    FORGE
#    SPIGOT
#    BUKKIT   (outdated)
#    VANILLA
minecraft_server_type=VANILLA

# Minecraft forge version (if you don't use forge this is ignored)
# Special values :
#    RECOMMENDED
minecraft_forge_version=
" > ${config_files_fullpath}

    echo "Default config file created at '${config_files_fullpath}'."
}

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

function print_config_params()
{
    echo "========================================================"
    echo "====              Config file settings              ===="
    echo "========================================================"
    echo "Check docker container base version   : $docker_check_for_updates"
    echo "Docker linux distribution auto-update : $linux_autoupdate"
    echo "Docker container name                 : $docker_name"
    echo "Minecraft server port                 : $minecraft_host_port"
    echo "Minecraft version                     : $minecraft_version"
    echo "Minecraft server type                 : $minecraft_server_type"

    if [ "$minecraft_server_type" == "FORGE" ]; then
        echo "Minecraft forge version               : $minecraft_forge_version"
    fi
    echo "========================================================"
}