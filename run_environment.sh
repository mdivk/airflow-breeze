#!/usr/bin/env bash
# Copyright 2018 Google LLC #
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Directory where the workspaces are located. For proper usage, this is
# the working directory.
WORKSPACE_DIRECTORY="$(pwd)"
# Name of the workspace. If not specified, default is "default".
WORKSPACE_NAME="default"
# If port forwarding is used, holds the port argument to pass to docker run.
DOCKER_PORT_ARG=""
# Holds the test target if the -t flag is used.
DOCKER_TEST_ARG="" # The tag of the docker image for running a workspace.
IMAGE_NAME="gcr.io/${PROJECT_ID}/airflow-upstream"
# If true, the docker image is rebuilt locally. Specified using the -r flag.
REBUILD=false
# String used to build the container run command.
FORMAT_STRING='docker run --rm -it '\
'-v %s/%s/incubator-airflow:/home/airflow/incubator-airflow '\
'-v %s/key:/home/airflow/.key '\
'-u airflow %s %s '\
'bash -c "sudo -E ./_init.sh && cd incubator-airflow && sudo -E su%s'

# Helper function for building the docker image locally.
build_local () {
  docker build . -t ${IMAGE_NAME}
  gcloud docker -- push ${IMAGE_NAME}
}

# Builds a docker run command based on settings and evaluates it.
# The workspace is run in an interactive bash session and the incubator-airflow
# directory is mounted. Also becomes superuser within container, installs
# dynamic dependencies, and sets up postgres. If specified, forwards ports for
# the webserver. If performing a test run, it is similar to the default run,
# but immediately executes a test, then exits.
run_container () {
  if [[ ! -z $DOCKER_TEST_ARG ]]; then
      POST_INIT_ARG=" -c './run_unit_tests.sh '"${DOCKER_TEST_ARG}"' -s --logging-level=DEBUG'\""
      else
      POST_INIT_ARG="\""
  fi
  CMD=$(printf "${FORMAT_STRING}" "${WORKSPACE_DIRECTORY}" "${WORKSPACE_NAME}" "${WORKSPACE_DIRECTORY}" "${DOCKER_PORT_ARG}" "${IMAGE_NAME}" "${POST_INIT_ARG}")
  eval ${CMD}
}

# Parse Flags
while getopts "ha:p:w:crt:" opt; do
  case $opt in
    h)
      echo "Usage ./run_environment.sh -a PROJECT_ID"
      echo "FLAGS"
      echo "-a"
      echo "Your GCP Project Id (required)"
      echo "-w"
      echo "Workspace name (ex: update_dataproc)"
      echo "-h"
      echo "Show this help message"
      echo "-p <port>"
      echo "Forward the webserver port to <port>"
      echo "-c"
      echo "Delete your local copy of the environment image"
      echo "-r"
      echo "Rebuild the environment image locally"
      echo "-t <target>"
      echo "Run the specified unit test target"
      exit 0
      ;;
    a)
      PROJECT_ID="${OPTARG}"
      ;;
    w)
      WORKSPACE_NAME="${OPTARG}"
      ;;
    p)
      DOCKER_PORT_ARG="-p 127.0.0.1:${OPTARG}:8080"
      ;;
    :)
      echo "Option -${OPTARG} requires an argument"
      exit 1
      ;;
     c)
      echo "Removing local image..."
      docker rmi ${IMAGE_NAME}
      exit 0
      ;;
     r)
      REBUILD=true
      ;;
     t)
      DOCKER_TEST_ARG="${OPTARG}"
      ;;
    \?)
      echo "Unknown option: -${OPTARG}"
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  echo "Missing project ID arg."
  exit 1
fi
IMAGE_NAME="gcr.io/${PROJECT_ID}/airflow-upstream"

# Check if the key directory is already made
if [[ ! -d "key" ]]; then
  mkdir key
fi

# Check if the workspace is already made
if [[ ! -d "$WORKSPACE_NAME" ]]; then
  mkdir -p "${WORKSPACE_NAME}/incubator-airflow" \
  && chmod 777 ${WORKSPACE_DIRECTORY}/${WORKSPACE_NAME}/incubator-airflow \
  && git clone https://github.com/apache/incubator-airflow.git "${WORKSPACE_NAME}/incubator-airflow"
fi

# Establish an image for the environment
if $REBUILD; then
  build_local
elif [[ -z "$(docker images -q ${IMAGE_NAME} 2> /dev/null)" ]]; then
  build_local
fi

run_container

