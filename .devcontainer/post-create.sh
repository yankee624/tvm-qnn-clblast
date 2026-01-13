#!/bin/bash
set -e

# Get the workspace directory (parent of .devcontainer)
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git config --global --add safe.directory "$WORKSPACE_DIR"

if [[ -n "$QUALCOMM_ID" && -n "$QUALCOMM_PASSWORD" ]]; then
    echo "*** Logging in with provided QUALCOMM_ID and QUALCOMM_PASSWORD ***"
    qpm-cli --login $QUALCOMM_ID $QUALCOMM_PASSWORD
else
    clear
    echo "*** Please enter the Qualcomm Developer ID and password to install the Hexagon SDK ***"
    echo "*** The login will take a few minutes to complete ***"
    qpm-cli --login
fi

qpm-cli --license-activate hexagonsdk6.x
yes | qpm-cli --install hexagonsdk6.x --version ${HEXAGON_SDK_VERSION}

pushd "$HEXAGON_SDK_ROOT/ipc/fastrpc/qaic"
make
popd


conda init
source ~/.bashrc
# allow conda activate command in shell script
source "$(conda info --base)/etc/profile.d/conda.sh"
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
conda create -n qnn -y python=3.10 -c pytorch
conda activate qnn
pip install torch==2.4.1
python "${QAIRT_SDK_ROOT}/bin/check-python-dependency"
