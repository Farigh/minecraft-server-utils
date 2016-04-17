#! /bin/bash

docker_hub_image=itzg/minecraft-server
resolved_script_path=`readlink -f $0`
current_script_dir=`dirname $resolved_script_path`
current_full_path=`readlink -e $current_script_dir`
docker_diff_path="$current_full_path/.utils/docker-diff"
default_server_data_dir="$current_full_path/server_data"
script_start_date=$(date +"%s")

# Includes
utils_dir="$current_full_path/.utils"

source "$utils_dir/functions.config.bash"
source "$utils_dir/vars.colors.bash"

# TODO: check current container config

config_dir="${current_full_path}/config"
config_file="${config_dir}/server.cfg"

if [ ! -f "$config_file" ]; then
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir" || (echo "${RED_COLOR}Error: Can't create configuration dir : '$config_dir'${RESET_COLOR}" && exit 1)
    fi

    echo "# Server deployment configuration file

# Docker container base auto-update
# Switch to 'true' to update docker as soon as a new version of the container is available
docker_autoupdate=false

# Docker linux distribution auto-update
# Switch to 'true' to updates Linux paquages on start
linux_autoupdate=false

# Docker container name (change it if you plan on running multiple configurations)
docker_name=minecraft_server

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
#    SPIGOT   (not supported yet)
#    BUKKIT   (not supported yet)
#    VANILLA
minecraft_server_type=VANILLA

# Minecraft forge version (if you don't use forge this is ignored)
# Special values :
#    RECOMMENDED
minecraft_forge_version=
" > ${config_file}

    echo "Default config file created at ${config_file}."
    echo "Edit it to fit your needs and run this script again"
    exit 0
fi

function print_config_params()
{
    echo "========================================================"
    echo "====              Config file settings              ===="
    echo "========================================================"
    echo "Docker container base auto-update     : $docker_autoupdate"
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

# out : docker_run_opt
function parse_config_file()
{
    docker_run_opt="-d -v $server_data_dir:/data"
    local error_occured=0

    if [ "$linux_autoupdate" != "" ]; then
        if [ "$linux_autoupdate" == "true" ]; then
            docker_run_opt="${docker_run_opt} -e KEEP_LINUX_UP_TO_DATE=true"
        elif [ "$linux_autoupdate" != "false" ]; then
            echo "${WHITE_BOLD_COLOR}Info: linux_autoupdate set to unknown value '$linux_autoupdate', ignoring it${RESET_COLOR}"
        fi
    fi

    if [ "$minecraft_version" == "" ]; then
        echo "${RED_COLOR}Error: minecraft_version can not be empty${RESET_COLOR}"
        error_occured=1
    else
        docker_run_opt="${docker_run_opt} -e VERSION=${minecraft_version}"
    fi

    if [ "$minecraft_server_type" == "" ]; then
        echo "${RED_COLOR}Error: minecraft_server_type can not be empty${RESET_COLOR}"
        error_occured=1
    else
        docker_run_opt="${docker_run_opt} -e TYPE=${minecraft_server_type}"
    fi

    if [ "$minecraft_server_type" == "FORGE" ]; then
        if [ "$minecraft_forge_version" == "" ]; then
            echo "${WHITE_BOLD_COLOR}Info: minecraft_forge_version not specified, using RECOMMENDED version${RESET_COLOR}"
            minecraft_forge_version=RECOMMENDED
        fi

        docker_run_opt="${docker_run_opt} -e FORGEVERSION=${minecraft_forge_version}"
    fi

    if [ "$minecraft_host_port" == "" ]; then
        echo "${RED_COLOR}Error: minecraft_host_port can not be empty${RESET_COLOR}"
        error_occured=1
    else
        docker_run_opt="${docker_run_opt} -p ${minecraft_host_port}:25565"
    fi

    # Add eula option
    docker_run_opt="${docker_run_opt} -e EULA=TRUE"

    if [ "$docker_name" == "" ]; then
        echo "${RED_COLOR}Error: docker_name can not be empty${RESET_COLOR}"
        error_occured=1
    else
        docker_run_opt="${docker_run_opt} --name ${docker_name}"
    fi

    # Add image to run
    docker_run_opt="${docker_run_opt} ${docker_hub_image}"

    # If error occured, exit the script
    if [ $error_occured -ne 0 ]; then
        echo "${RED_COLOR}Error occurred, exiting${RESET_COLOR}"
        exit 1
    fi
}

function check_if_not_already_started()
{
    if [ "$(docker inspect -f {{.State.Running}} $docker_name)" == "true" ]; then
        echo "${RED_COLOR}Error: container '$docker_name' is already running${RESET_COLOR}"
        exit 1
    fi
}

#  in : force_docker_update (true/false)
# out : is_docker_run_needed (0/1)
function pull_docker()
{
    local force_docker_update=$1
    local docker_find_image=`docker images | grep "^$docker_hub_image "`
    # Initialize to 0
    is_docker_run_needed=0

    if [ "$force_docker_update" != "true" ] && [ "$docker_images_out" != "" ]; then
        # only pull docker image it does not exist or update is activated
        return
    fi

    echo "=== Updating docker container for '$docker_hub_image' ..."
    docker pull $docker_hub_image

    if [ "$docker_images_out" != "" ]; then
        # First pull, don't go any further
        is_docker_run_needed=1
        return
    fi

    echo "=== Checking docker hub version for '$docker_hub_image' ..."

    local server_version=`docker inspect --format "{{.Id}}" $docker_hub_image`

    local docker_ps=`docker ps -a | grep $docker_name`

    echo "  Latest server version = $server_version"

    if [ "$docker_ps" != "" ]; then
        docker_container_id=`echo $docker_ps | cut -d' ' -f 1`
        current_version=`docker inspect --format "{{.Image}}" $docker_container_id`

        echo "  Current version       = $current_version"

        if [ "$server_version" != "$current_version" ]; then
            echo -n "Version miss-match, removing container and image "
            docker rm $docker_container_id

            date=`date +'%Y-%m-%d'`
            mkdir -p "$server_data_dir-backups"
            backup_dir_template="$server_data_dir-backups/$date"
            backup_dir="$backup_dir_template"
            i=1
            # If dir already exist append number to avoid collision
            while [ -d "$backup_dir" ]; do
                backup_dir="${backup_dir_template}-$i"
                ((i++))
            done

            echo "Backup files to $backup_dir ..."
            cp -r $server_data_dir $backup_dir
            is_docker_run_needed=1
        fi
    else
        is_docker_run_needed=1
    fi
}

function initial_run_docker()
{
    echo "=== '$docker_name' initial run...."
    docker_container_id=`docker run $docker_run_opt`
    # Sleep 10 seconds so it has time to create files
    sleep 10
    echo "=== Done"

    # Docker needs to be stopped as it's runned started
    echo "=== Stopping '$docker_name' to apply patches...."
    docker stop $docker_name

    # Reset last start time
    script_start_date=$(date +"%s")

    echo "=== Applying patches...."
    docker_file_location="/var/lib/docker/aufs/diff/$docker_container_id"

    # Wait a bit for file to be flushed here
    sleep 1
    echo "docker_file_location = $docker_file_location"
    patch -d $docker_file_location -p1 < $docker_diff_path/start-minecraft.patch
    cp $docker_diff_path/start $docker_file_location
}

function get_server_launching_status()
{
    declare -A server_launch_animated_steps
    server_launch_animated_steps[0]="|"
    server_launch_animated_steps[1]="/"
    server_launch_animated_steps[2]="-"
    server_launch_animated_steps[3]="\\"
    local server_launch_animated_steps_index=0
    local server_log_file="$server_data_dir/logs/latest.log"
    local forge_server_log_file="$server_data_dir/logs/fml-server-latest.log"

    # Read default log file
    local tail_options="-n 1 -f $server_log_file"
    local forge_initialisation_done=1
    local mc_server_initialisation_done=0
    local waiting_count=0

    # Wait for log files to exist and up-to-date
    while [ ! -f "$server_log_file" ] \
       || [ $(stat -c '%Y' $server_log_file) -le $script_start_date ];
    do
        if [ $waiting_count -eq 0 ]; then
            printf "  Running server...%-45s\r" "( ${server_launch_animated_steps[$server_launch_animated_steps_index]} waiting for server logs)"
            server_launch_animated_steps_index=$(((server_launch_animated_steps_index + 1) % 4))
        fi

        (((waiting_count + 1) % 5))

        sleep 0.1
    done

    # Add forge log file if using it
    if [ "$minecraft_server_type" == "FORGE" ]; then
        tail_options="$tail_options -f $forge_server_log_file"
        forge_initialisation_done=0

        # Wait for log files to exist and up-to-date
        while [ ! -f "$forge_server_log_file" ] \
           || [ $(stat -c '%Y' $forge_server_log_file) -le $script_start_date ];
        do
            if [ $waiting_count -eq 0 ]; then
                printf "  Running server...%-45s\r" "( ${server_launch_animated_steps[$server_launch_animated_steps_index]} waiting for forge logs)"
                server_launch_animated_steps_index=$(((server_launch_animated_steps_index + 1) % 4))
            fi

            (((waiting_count + 1) % 5))
            sleep 0.1
        done
    fi

    # Parse log file
    local server_log_line
    local server_status="Starting server..."
    local forge_status="Forge: Initializing..."
    local displayed_status
    local previous_length=0
    local blank_line='                                                                                '

    while read server_log_line; do
        # Server started
        if [[ "$server_log_line" == *"Done"*"For help, type"* ]]; then
            server_status="Server started !"
            mc_server_initialisation_done=1
        fi

        displayed_status="$server_status"

        # Looking for forge events
        if [ $forge_initialisation_done -ne 1 ]; then
            if [[ "$server_log_line" == *"Attempting to load mods"* ]]; then
                forge_status="Forge: Scanning for mods..."
            elif [[ "$server_log_line" == *"Found translations"* ]]; then
                forge_status="Forge: Looking for localization..."
            elif [[ "$server_log_line" == *"Sending event FMLConstructionEvent"* ]]; then
                forge_status="Forge: Constructing mods..."
            elif [[ "$server_log_line" == *"Sending event FMLPreInitializationEvent"* ]]; then
                forge_status="Forge: Preinitializing mods..."
            elif [[ "$server_log_line" == *"Sending event FMLInitializationEvent"* ]]; then
                forge_status="Forge: Initializing mods..."
            elif [[ "$server_log_line" == *"Sending event IMCEvent"* ]]; then
                forge_status="Forge: Establishing comm with mods..."
            elif [[ "$server_log_line" == *"Sending event FMLPostInitializationEvent"* ]]; then
                forge_status="Forge: Postinitializing mods..."
            elif [[ "$server_log_line" == *"Sending event FMLLoadCompleteEvent"* ]]; then
                forge_status="Forge: Complete loading mods..."
            elif [[ "$server_log_line" == *"Sending event FMLModIdMappingEvent"* ]]; then
                forge_status="Forge: Mapping mod ids..."
            elif [[ "$server_log_line" == *"Sending event FMLServerStartingEvent"* ]]; then
                forge_status="Forge: Sending server started event..."
            elif [[ "$server_log_line" == *"Bar Finished: ServerStarted "* ]]; then
                forge_status="Forge started !"
                forge_initialisation_done=1
            fi

            displayed_status="$server_status $forge_status"
        fi

        # Print on the same line erasing previous chars
        local status="  Running server...( ${server_launch_animated_steps[$server_launch_animated_steps_index]} $displayed_status)"
        local trailling_blanks=${blank_line:${#status}}
        echo -ne "$status$trailling_blanks\r"
        server_launch_animated_steps_index=$(((server_launch_animated_steps_index + 1) % 4))

        if [ $mc_server_initialisation_done -eq 1 ] && [ $forge_initialisation_done -eq 1 ]; then
            # Done, print newline
            echo ""
            break
        fi

    # Read log files
    done < <(tail $tail_options)

}

function start_docker()
{
    echo "=== Running minecraft server...."
    docker start $docker_name > /dev/null

    # Check for update completion
    echo -ne "  Updating Linux packages...\r"
    # Wait for start script to run
    sleep 2

    declare -A animated_steps
    animated_steps[0]="|"
    animated_steps[1]="/"
    animated_steps[2]="-"
    animated_steps[3]="\\"
    local animate_index=0
    while [ "`docker exec -i -t $docker_name ps ax -o command | grep 'apt-get'`" != "" ]; do
        local update_step="retreiving package lists"
        local update_status=$(docker exec -i -t $docker_name ps ax -o command | grep 'apt-get' | grep 'upgrade')
        if [ "$update_status" != "" ]; then
            local update_ps_ouput=$(docker exec -i -t $docker_name  bash -c "ps ax -o command | grep dpkg | grep -v grep | head -n 1")
            update_step=$(echo "$update_ps_ouput" | awk -F " " '{print $NF}' | sed -e 's/[^[:alnum:]+-.]//g')

            local update_step_size=${#update_step}
            # Truncate package name to avoid to long prints
            if [ $update_step_size -gt 40 ]; then
                local update_step_begin=${update_step:0:18}
                local update_step_end=${update_step:(-18)}
                update_step="${update_step_begin}...${update_step_end}"
            fi
        fi
        printf "  Updating Linux packages...%-45s\r" "( ${animated_steps[$animate_index]} $update_step)"
        animate_index=$(((animate_index + 1) % 4))
        sleep 1
    done
    printf "  Updating Linux packages...%-45s\n" "Done"

    # Check for server running status
    echo -ne "  Running server...( ${animated_steps[$animate_index]} starting java process)\r"
    animate_index=$(((animate_index + 1) % 4))
    # Wait for java to start
    while [ "`docker exec -i -t $docker_name ps ax -o command | grep 'java'`" == "" ]; do
        sleep 1
        printf "  Running server...%-45s\r" "( ${animated_steps[$animate_index]} starting java process)"
        animate_index=$(((animate_index + 1) % 4))
    done
    sleep 1

    get_server_launching_status

    echo "=== Done"
}

################################################
###                   MAIN                   ###
################################################

source ${config_file}

load_config_file $config_dir $default_server_data_dir

# Create server data dir on first run
if [ ! -d "$server_data_dir" ]; then
    if [ -e "$server_data_dir" ]; then
        echo "${RED_COLOR}Error: '$server_data_dir' exists but is not a directory${RESET_COLOR}"
    else
        echo "${CYAN_COLOR}Info: Creating directory '$server_data_dir'${RESET_COLOR}"
        mkdir -p "$server_data_dir" || (echo "${RED_COLOR}Error: Can't create '$server_data_dir'${RESET_COLOR}" && exit 1)
    fi
fi

print_config_params

parse_config_file

check_if_not_already_started

pull_docker $docker_autoupdate

if [ "$is_docker_run_needed" == "1" ]; then
    initial_run_docker
fi

start_docker