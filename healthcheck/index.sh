#!/bin/bash

# exit when any command fails
set -e

# get where the script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

bash $DIR/connected-to-warp.sh

# apply host connectivity fixes when enabled
if [ -n "$BETA_FIX_HOST_CONNECTIVITY" ]; then
    bash $DIR/fix-host-connectivity.sh
fi

# always ensure container ports are publicly accessible
bash $DIR/fix-public-access.sh
