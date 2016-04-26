#! /bin/bash

docker_hub_image=itzg/minecraft-server
resolved_script_path=`readlink -f $0`
current_script_dir=`dirname $resolved_script_path`
current_full_path=`readlink -e $current_script_dir`
docker_diff_path="$current_full_path/.utils/docker-diff"
script_start_date=$(date +"%s")
erase_current_line_sequence="\r$(tput el)" # clear to end of line

# Includes
utils_dir="$current_full_path/.utils"

source "$utils_dir/functions.config.bash"
source "$utils_dir/vars.colors.bash"
source "$utils_dir/vars.default.bash"

################################################
###                FUNCTIONS                 ###
################################################

# out : docker_run_opt
function create_docker_options()
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
    docker_run_opt="${docker_run_opt} ${docker_hub_image}@${docker_commit}"

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

function check_if_port_is_already_used()
{
    # List all running docker container with same port
    local docker_if_running_cond="{{if eq true .State.Running }}"
    local docker_display_code="{{.Name}} {{ (index (index .HostConfig.PortBindings \"25565/tcp\") 0).HostPort }}"
    local docker_inspect_result=$(docker inspect -f "${docker_if_running_cond}${docker_display_code}{{end}}" $(docker ps -aq))
    local filtered_result=$(echo -e "$docker_inspect_result" | grep " ${minecraft_host_port}$")

    if [ "${filtered_result}" != "" ]; then
        echo "${RED_COLOR}Error: Running docker container already listening on port ${minecraft_host_port}:"
        echo "${filtered_result}${RESET_COLOR}"
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

    if [ "$docker_check_for_updates" == "true" ] \
       || [ "$force_docker_update" == "true" ]   \
       || [ "$docker_find_image" == "" ]; then
        # Only pull docker image if it does not exist, check for update option is enabled or force update is activated
        echo "=== Pulling docker container from '$docker_hub_image' ..."
        docker pull $docker_hub_image
    fi

    if [ "$docker_find_image" == "" ]; then
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
        echo "  Configured version    = $docker_commit"

        # TODO: check current container config
        if [ "$server_version" != "$docker_commit" ]; then
            # Update required, backup config and modify docker_commit
            if [ "$force_docker_update" == "true" ]; then
                docker_commit=$server_version
                # Backup config file
                cp -f "${config_file}" "${config_file}.bak"
                sed -i "s/docker_commit=[a-fA-F0-9]*/docker_commit=${server_version}/" "${config_file}"
                # Update version in config
            # No update required, just print if version differs
            elif [ "$docker_check_for_updates" == "true" ]; then
                echo "${CYAN_COLOR}Info: A new version of the docker container is available${RESET_COLOR}"
                echo "${CYAN_COLOR}      You can rerun this script using --force-update option to use it${RESET_COLOR}"
                echo  "${RED_COLOR}      /!\\${CYAN_COLOR} If you do so, it might not work properly anymore${RESET_COLOR}"
            fi
        fi

        if [ "$docker_commit" != "$current_version" ]; then
            echo -n "Updating to '$docker_commit' revision, removing container and image "
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

function docker_initial_run()
{
    # TODO: get this location from docker info
    local docker_diff_dir="/var/lib/docker/aufs/diff/"
    ls $docker_diff_dir 2>/dev/null
    ls_exit_code=$?

    if [ $ls_exit_code -gt 0 ]; then
        echo "${RED_COLOR}Error: can't access '$docker_diff_dir', consider reruning as root${RESET_COLOR}"
        exit 1
    fi

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
            echo -ne "${erase_current_line_sequence}  Running server...( ${server_launch_animated_steps[$server_launch_animated_steps_index]} waiting for server logs)"
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
                echo -ne "${erase_current_line_sequence}  Running server...( ${server_launch_animated_steps[$server_launch_animated_steps_index]} waiting for forge logs)"
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
        echo -ne "${erase_current_line_sequence}  Running server...( ${server_launch_animated_steps[$server_launch_animated_steps_index]} $displayed_status)"
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
    echo -ne "${erase_current_line_sequence}  Updating Linux packages..."
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
        echo -ne "${erase_current_line_sequence}  Updating Linux packages...( ${animated_steps[$animate_index]} $update_step)"
        animate_index=$(((animate_index + 1) % 4))
        sleep 1
    done
    echo -e "${erase_current_line_sequence}  Updating Linux packages...Done"

    # Check for server running status
    echo -ne "  Running server...( ${animated_steps[$animate_index]} starting java process)"
    animate_index=$(((animate_index + 1) % 4))
    # Wait for java to start
    while [ "`docker exec -i -t $docker_name ps ax -o command | grep 'java'`" == "" ]; do
        sleep 1
        echo -ne "${erase_current_line_sequence}  Running server...( ${animated_steps[$animate_index]} starting java process)"
        animate_index=$(((animate_index + 1) % 4))
    done
    sleep 1

    get_server_launching_status

    echo "=== Done"
}

function print_usage()
{
    echo "Usage: $0 [OPTION]..."
    echo "Runs a minecraft server using docker"
    echo ""
    echo "-f, --force-update  force docker image update"
    echo "-h, --help          display this help and exit"
}

################################################
###                  GETOPT                  ###
################################################

force_update="false"
while getopts ":fh-:" parsed_option; do
    case "${parsed_option}" in
        # Long options
        -)
            case "${OPTARG}" in
                force-update)
                    force_update="true"
                ;;
                help)
                    print_usage
                    exit 0
                ;;
                *)
                    echo "Unknown option --${OPTARG}"
                    print_usage
                    exit 1
                ;;
            esac
        ;;
        # Short options
        f)
            force_update="true"
        ;;
        h)
            print_usage
            exit 0
        ;;
        *)
            echo "Unknown option -${parsed_option}"
            print_usage
            exit 1
        ;;
    esac
done

################################################
###                   MAIN                   ###
################################################

config_dir="${current_full_path}/config"
config_file="${config_dir}/server.cfg"

if [ ! -f "$config_file" ]; then
    generate_default_config_file $config_file
    echo "Edit it to fit your needs and run this script again"
    exit 0
fi

source ${config_file}

load_config_file $config_dir $default_server_data_dir

# Create server data dir on first run
if [ ! -d "$server_data_dir" ]; then
    if [ -e "$server_data_dir" ]; then
        echo "${RED_COLOR}Error: '$server_data_dir' exists but is not a directory${RESET_COLOR}"
        exit 1
    else
        echo "${CYAN_COLOR}Info: Creating directory '$server_data_dir'${RESET_COLOR}"
        mkdir -p "$server_data_dir" || (echo "${RED_COLOR}Error: Can't create '$server_data_dir'${RESET_COLOR}" && exit 1)
    fi
fi

print_config_params

check_if_not_already_started
check_if_port_is_already_used

pull_docker $force_update

if [ "$is_docker_run_needed" == "1" ]; then
    create_docker_options
    docker_initial_run
fi

start_docker
