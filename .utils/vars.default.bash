#! /bin/bash

if [ "$current_full_path" == "" ]; then
    echo "Error: 'current_full_path' is not set while including vars.default.bash"
    exit 1
fi

default_server_data_dir="$current_full_path/server_data"