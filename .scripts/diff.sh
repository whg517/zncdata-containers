#!/bin/bash

set -e
set -o pipefail

CI_DEBUG=${CI_DEBUG:-false}

# If CI_DEBUG is set, enable debug mode
if [ "$CI_DEBUG" = "true" ]; then
  set -x
fi

function main () {
  local usage="
Usage: command [OPTIONS]

Get change targets between two commits.

Arguments:

Options:
  -h,  --help                     Show this message
  -c,  --compare                  The compare commit, default to HEAD^
  -b,  --base                     The base commit, default to HEAD

"

  local compare="HEAD^"
  local base="HEAD"

  # Parse arguments
  while [ "$1" != "" ]; do
    case $1 in
      -c | --compare )
        shift
        compare=$1
        ;;
      -b | --base )
        shift
        base=$1
        ;;
      -h | --help )
        echo "$usage"
        exit 0
        ;;
      * )
        echo "Error: Invalid argument"
        echo "$usage"
        exit 1
        ;;
    esac
    shift
  done

  # Get changed product versions
  get_changed_versions $base $compare
}


# Get changed product versions.
# Arguments:
#   $1: base_sha, the base commit
#   $2: compare_sha, the compare commit
# Returns:
#   JSON: The changed product version JSON object, eg: ["kubedoop-base:1.0.0","vector:0.39.0"]
function get_changed_versions () {
  local base_sha=$1
  local compare_sha=$2

  # check arguments
  if [ -z "$base_sha" ] || [ -z "$compare_sha" ]; then
    echo "Error: base_sha and compare_sha are required" >&2
    exit 1
  fi

  local product_versions=$(get_product_versions)
  # Get changed products, it is JSON array
  local changed_products=$(get_changed_products $base_sha $compare_sha)

  # Initialize empty JSON array
  local result="[]"

  # Loop through each changed product
  for product in $(echo $changed_products | jq -r '.[]'); do
    # Get versions for the product
    local versions=$(jq -r --arg prod "$product" '.[$prod] | .[]' <<< $product_versions)

    # Convert versions to JSON array
    local versions_json=$(jq -n '[]')
    for version in $versions; do
      versions_json=$(jq --arg prod "$product" --arg ver "$version" '. + ["\($prod):\($ver)"]' <<< $versions_json)
    done

    # Add product and its versions to result
    result=$(jq --argjson vers "$versions_json" '. + $vers' <<< $result)
  done

  echo "INFO: Changed product versions: $(echo "$result" | jq -c '.')" >&2
  # return converted JSON array
  echo $(jq -c <<< $result)
}

# Get product versions to json object from project.yaml and versions.yaml,
# product.yaml defines the products name.
# versions.yaml location is in the same directory as product name.
# The result json object is like:
# {"kubedoop-base":["1.0.0"],"vector":["0.39.0","0.41.0"]}
#
# Arguments:
#   None
# Returns:
#   JSON: The product versions JSON object, eg: {"kubedoop-base":["1.0.0"],"vector":["0.39.0","0.41.0"]}
function get_product_versions () {
  # Read products from project.yaml
  local products=$(yq -r '.products[]' project.yaml | grep -v '^#')

  # Initialize empty JSON object
  local result="{}"

  # Loop through each product
  for product in $products; do
    # Check if versions.yaml exists for the product
    local product_versions_file="${product}/versions.yaml"
    if [ -f "$product_versions_file" ]; then
      # Get versions array for the product
      local versions=$(yq -r '.versions[].product' "$product_versions_file")

      # Convert versions to JSON array
      local versions_json=$(jq -n '[]')
      for version in $versions; do
        versions_json=$(jq --arg ver "$version" '. + [$ver]' <<< $versions_json)
      done

      # Add product and its versions to result
      result=$(echo $result | jq --arg prod "$product" --argjson vers "$versions_json" '. + {($prod): $vers}')
    fi
  done

  echo "INFO: Product versions: $(echo "$result" | jq -c '.')" >&2
  # return converted JSON object
  echo $(jq -c <<< $result)
}


# Use git diff to get the changed products between two commits, and return the changed products.
# Arguments:
#   $1: base_sha, the base commit
#   $2: compare_sha, the compare commit
# Returns:
#   JSON: The changed products, it is JSON array, eg: ["kubedoop-base","vector"]
function get_changed_products () {
  local base_sha=$1
  local compare_sha=$2

  # check arguments
  if [ -z "$base_sha" ] || [ -z "$compare_sha" ]; then
    echo "Error: base_sha and compare_sha are required" >&2
    exit 1
  fi

  # Read products and global paths from project.yaml
  local products=$(yq -r -o=json '.products' project.yaml | grep -v '^#')
  echo "INFO: All products: $(echo "$products" | jq -c '.')" >&2
  local global_paths=$(yq -r -o=json '.global-paths' project.yaml | grep -v '^#')
  echo "INFO: Global paths: $(echo "$global_paths" | jq -c '.')" >&2

  # Get the changed path
  echo "INFO: Comparing $base_sha and $compare_sha" >&2
  local changed_paths=$(git diff --name-only $base_sha $compare_sha | xargs -I {} dirname {} | sort -u | uniq)
  echo "INFO: Changed paths: $changed_paths" >&2

  # Check if any changed path matches global paths
  for changed_path in $changed_paths; do
    for global_path in $(echo $global_paths | jq -r '.[]'); do
      echo "INFO: Comparing with $changed_path =~ $global_path" >&2
      if [[ "$changed_path" =~ ^$global_path ]]; then
        # If matches global path, return all products
        echo $products
        return 0
      fi
    done
  done

  # Initialize empty JSON array for changed products
  local result="[]"

  # If no global path matches, check product matches
  for changed_path in $changed_paths; do
    if echo "$products" | jq -e --arg path "$changed_path" '.[] | select(. == $path)' > /dev/null; then
      result=$(echo $result | jq --arg prod "$changed_path" '. + [$prod]')
    fi
  done

  echo "INFO: Changed products: $(echo $result | jq -c '.')" >&2
  echo $result
}


main "$@"
