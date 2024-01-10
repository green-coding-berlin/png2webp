#!/bin/bash

set -euo pipefail

# These can be set with paramters
WEBP_QUALITY=80
DELETE_FILE=false

# Vars to hold the sums of filesizes
TOTAL_ORIGINAL_SIZE=0
TOTAL_WEBP_SIZE=0
TOTAL_UNREFERENCED=0

while getopts "dq:" opt; do
  case $opt in
    d) DELETE_FILE=true ;;
    q) WEBP_QUALITY="$OPTARG"
       if ! [[ "$WEBP_QUALITY" =~ ^[0-9]+$ ]]; then
         echo "Error: Quality must be an integer."
         exit 1
       fi
       ;;
    \?) echo "Invalid option: -$OPTARG" >&2
        exit 1 ;;
  esac
done

shift $((OPTIND - 1))

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <git-repo-url-or-local-path>"
    exit 1
fi

INPUT=$1

if command -v cwebp >/dev/null 2>&1; then
    CONVERT_CMD="cwebp"
else
    echo "Error: cwebp (ImageMagick) is available. Please install and try again."
    exit 1
fi

if [[ "$INPUT" == http://* ]] || [[ "$INPUT" == https://* ]] || [[ "$INPUT" == git://* ]]; then
    REPO_URL=$INPUT
    REPO_NAME=$(basename "$REPO_URL" .git)

    git clone "$REPO_URL"
    if [ $? -ne 0 ]; then
        echo "Failed to clone repository."
        exit 1
    fi

    cd "$REPO_NAME" || exit
else
    if [ ! -d "$INPUT" ]; then
        echo "Provided path does not exist."
        exit 1
    fi

    cd "$INPUT" || exit
fi

replace_references() {

    local original_path=$2
    local original_file=$(basename "$1")
    local new_file=$(basename "$2")

    if grep_output=$(grep -Rl --exclude-dir=".git" --exclude="*.webp" --exclude="*$(basename "$0")" "$original_file" .); then
        echo "$grep_output" | tr '\n' '\0' | xargs -0 sed -i '' "s|$original_file|$new_file|g"
    else
        echo "No references to $original_file found."
        if [ "$DELETE_FILE" = true ]; then
            if ! grep_webp_output=$(grep -Rl --exclude-dir=".git" --exclude="*.webp" --exclude="*$(basename "$0")" "$new_file" .); then
                local original_size=$(stat -f%z "$original_path")
                TOTAL_UNREFERENCED=$((TOTAL_UNREFERENCED + original_size))
                rm "$original_path"
                echo "Deleted: $original_path"
            fi
        fi
    fi
}

convert_to_webp() {
    local img_file=$1
    local new_file=$2

    echo "Converting $img_file -> $new_file"
    cwebp -mt -quiet -q "$WEBP_QUALITY" "$img_file" -o "$new_file"

    local original_size=$(stat -f%z "$img_file")
    local webp_size=$(stat -f%z "$new_file")

    TOTAL_ORIGINAL_SIZE=$((TOTAL_ORIGINAL_SIZE + original_size))
    TOTAL_WEBP_SIZE=$((TOTAL_WEBP_SIZE + webp_size))

    if [ "$DELETE_FILE" = true ]; then
        echo "Deleted: $img_file"
        rm "$img_file"
    fi
}

while IFS= read -r -d $'\0' img_file; do
    original_file="${img_file#./}"
    new_file="${original_file%.*}.webp"
    convert_to_webp "$original_file" "$new_file"
    replace_references "$original_file" "$new_file"
    echo ""
done < <(find . -type f \( -iname "*.png" -o -iname "*.jpg" \) -print0)

TOTAL_ORIGINAL_SIZE_MB=$(echo "scale=2; $TOTAL_ORIGINAL_SIZE / 1048576" | bc)
TOTAL_WEBP_SIZE_MB=$(echo "scale=2; $TOTAL_WEBP_SIZE / 1048576" | bc)
TOTAL_UNREFERENCED_MB=$(echo "scale=2; $TOTAL_UNREFERENCED / 1048576" | bc)
SPACE_SAVED_MB=$(echo "scale=2; $TOTAL_ORIGINAL_SIZE_MB - $TOTAL_WEBP_SIZE_MB" | bc)

echo "Total deleted unused images: $TOTAL_UNREFERENCED_MB MB"
echo "Total original size: $TOTAL_ORIGINAL_SIZE_MB MB"
echo "Total WEBP size: $TOTAL_WEBP_SIZE_MB MB"
echo "Total space saved: $SPACE_SAVED_MB MB"
