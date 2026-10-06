#!/bin/sh
# Makes an API key for the PK Reference server, and the hash the server is given.
#
#   backend/scripts/new-api-key.sh
#
# The key goes into the app (Settings > PK Reference Server > API Key) and nowhere else. The hash
# goes into the server's PKREF_API_KEY_HASHES (comma-separated, one per key), in an untracked .env.
# Keep the key out of the repository, chats and screenshots; to retire it, remove its hash.
set -eu
key="pkr_$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"
hash=$(printf '%s' "$key" | shasum -a 256 | cut -d ' ' -f 1)
printf 'Key (for the app):            %s\n' "$key"
printf 'Hash (PKREF_API_KEY_HASHES):  %s\n' "$hash"
