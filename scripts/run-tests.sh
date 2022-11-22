#!/usr/bin/env bash
set -eo pipefail

if [ -z "$OP_CONNECT_TOKEN_FILE" ]; then
  OP_CONNECT_TOKEN_FILE=".op_connect_token_ansible"
fi

if [ -f "$OP_CONNECT_TOKEN_FILE" ] && [ -z "$OP_CONNECT_TOKEN" ]; then
  echo "Setting OP_CONNECT_TOKEN from ${OP_CONNECT_TOKEN_FILE}"
  OP_CONNECT_TOKEN="$(cat $OP_CONNECT_TOKEN_FILE)"
fis

if [ ! docker info >/dev/null 2>&1 ] && [ -z $ANSIBLE_TEST_USE_VENV ]; then
    echo "==> [ERROR] Docker must be running before executing tests."
    exit 1
fi

if ! command -v ansible-test &> /dev/null; then
  echo "==> [ERROR] ansible-test not found in PATH. Please install or update PATH variable."
  exit 1
fi

# Only allow test types of "units" or "integration"
if [[ -z ${1+x} ]]; then
  echo "[ERROR] Usage: run-tests.sh units|integration|sanity"
  exit 1
elif [[ "$1" == "units" || "$1" == "integration" || "$1" == "sanity" ]]; then
  TEST_SUITE="$1"
else
  echo "[ERROR] Usage: run-tests.sh units|integration|sanity"
  exit 1
fi

COLLECTION_NAMESPACE="onepassword"
PACKAGE_NAME="connect"

# Collection will be copied to this path so that we can
# set the correct ANSIBLE_COLLECTION_PATH for tests.
TMP_DIR_PATH="$(mktemp -d)"
TMP_COLLECTIONS_PATH="${TMP_DIR_PATH}/collections/ansible_collections/${COLLECTION_NAMESPACE}/${PACKAGE_NAME}"

PATH_TO_PACKAGES="$(git rev-parse --show-toplevel)"

# Use a python3-compatible container
# https://docs.ansible.com/ansible/latest/dev_guide/testing_integration.html#container-images
DOCKER_IMG="default"

# Minimum python version we support
MIN_PYTHON_VERSION="3.6"

function _cleanup() {
  rm -r "${TMP_DIR_PATH}"
}

function inject_env_vars() {

  if [ "${TEST_SUITE}" != "integration" ]; then
    return
  fi

  if [ -z "${OP_CONNECT_HOST+x}" ] || [ -z "${OP_CONNECT_TOKEN+x}" ]; then
      echo "==> [ERROR] OP_CONNECT_HOST and OP_CONNECT_TOKEN environment vars are required."
      exit 1
  fi

  cd "${TMP_COLLECTIONS_PATH}/"
  # replace placeholders with env vars for integration tests
  find ./tests/integration/ -type f -name "*.yml" -exec sed -i "s|__OP_CONNECT_HOST__|${OP_CONNECT_HOST}|g" {} +
  find ./tests/integration/ -type f -name "*.yml" -exec sed  -i "s|__OP_CONNECT_TOKEN__|${OP_CONNECT_TOKEN}|g" {} +

  if [ ! -z "${OP_VAULT_ID+x}" ]; then
    find ./tests/integration -type f -name "*.yml" -exec sed -i "s|__OP_VAULT_ID__|${OP_VAULT_ID}|g" {} +
  fi

  if [ ! -z "${OP_VAULT_NAME+x}" ]; then
    find ./tests/integration -type f -name "*.yml" -exec sed -i "s|__OP_VAULT_NAME__|${OP_VAULT_NAME}|g" {} +
  fi
}

function setup() {
  # ansible-test has specific path requirements for Ansible Collection integration tests
  mkdir -p "${TMP_COLLECTIONS_PATH}"

  # copy all connect/{package names} folders into temp dir
  rsync -ar --exclude '.*' "${PATH_TO_PACKAGES}/" "${TMP_COLLECTIONS_PATH}"
}

function prepare_integration_config() {
  truncate -s 0 ${TMP_COLLECTIONS_PATH}/test/ingration/integration-config.yml
  while read -r line; do
    echo $line
    eval 'echo "'"${line}"'" >> "'"${TMP_COLLECTIONS_PATH}"'"/test/integration/integration_config.yml'
  done

  cat ${TMP_COLLECTIONS_PATH}/test/integration/integration_config.yml
}

function do_tests() {
  # `zz` is a throwaway value here
  # When the `if` cond sees `zz` it goes into the `else` block.
  if [ -z "${ANSIBLE_COLLECTIONS_PATH+zz}" ]; then
    collection_path="${TMP_DIR_PATH}"
  else
    collection_path="${ANSIBLE_COLLECTIONS_PATH}:${TMP_DIR_PATH}"
  fi

  cd "${TMP_COLLECTIONS_PATH}/"

  echo "Using Server $OP_CONNECT_HOST"
  echo "Token: $OP_CONNECT_TOKEN"
  echo "Vault: $OP_CONNECT_VAULT_NAME ($OP_CONNECT_VAULT_NAME)"

  echo "Initializing ansible-test ${TEST_SUITE} runner..........."

  if [ -z "$ANSIBLE_TEST_USE_VENV" ]; then
    ANSIBLE_COLLECTIONS_PATH="${collection_path}" ansible-test "${TEST_SUITE}" --docker "${DOCKER_IMG}" --python "${MIN_PYTHON_VERSION}" --docker-network ansible-onepasswordconnect-collection_default
  else
    ANSIBLE_COLLECTIONS_PATH="${collection_path}" ansible-test "${TEST_SUITE}" --venv --python "${MIN_PYTHON_VERSION}"
  fi
}

trap _cleanup EXIT

setup
inject_env_vars
do_tests
