#!/bin/bash
# gh-api.sh — GitHub API 辅助（自动读 token）
# 用法：
#   ./scripts/gh-api.sh GET  /repos/BH2VOQ/PS3Eye-VirtualCam/releases/367686947
#   ./scripts/gh-api.sh POST /repos/.../releases -d '{...}'
#   ./scripts/gh-api.sh DELETE /repos/.../assets/123
#   ./scripts/gh-api.sh UPLOAD /repos/.../releases/367686947/assets?name=x.dmg <file>
set -e
TOKEN=$(cat "$HOME/.config/github/gh-token")
METHOD=$1; PATH2=$2; BODY=$3; FILE=$4
case "$METHOD" in
  GET)     curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com$PATH2" ;;
  POST)    if [[ "$BODY" == @* ]]; then curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" --data @"${BODY:1}" "https://api.github.com$PATH2"; else curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" -d "$BODY" "https://api.github.com$PATH2"; fi ;;
  PATCH)   if [[ "$BODY" == @* ]]; then curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" --data @"${BODY:1}" "https://api.github.com$PATH2"; else curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" -d "$BODY" "https://api.github.com$PATH2"; fi ;;
  DELETE)  curl -s -X DELETE -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -w "HTTP %{http_code}\n" "https://api.github.com$PATH2" ;;
  UPLOAD)  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/zip" --data-binary @"$FILE" "https://uploads.github.com$PATH2" ;;
esac
