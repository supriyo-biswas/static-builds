#shellcheck shell=bash

symlink_dups() {
    prev_file=''
    prev_hash=''

    find "$1" -type f -print0 | \
        xargs -0 sha256sum | \
        sort | \
        uniq -w64 -d --all-repeated=separate | \
        while read -r line; do
        hash=$(echo "$line" | awk '{ print $1; }')
        if [ "$line" = '' ]; then
            prev_hash=''
            continue
        fi

        if [ "$prev_hash" = '' ]; then
            prev_hash="$hash"
            prev_file=$(echo "$line" | awk '{ print $2; }')
            continue
        fi

        file=$(echo "$line" | awk '{ print $2; }')
        ln -srf "$prev_file" "$file"
    done
}

convert_symlinks() {
  find "$1" -type l -print0 | while IFS= read -r -d '' symlink; do
    target=$(readlink "$symlink")
    if [[ "$target" == /* ]]; then
      symlink_dir=$(dirname "$symlink")
      relative_target=$(realpath --relative-to="$symlink_dir" "$target")
      rm "$symlink"
      ln -sv "$relative_target" "$symlink"
    fi
  done
}
