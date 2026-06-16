cat() {
  if command -v smartcat >/dev/null 2>&1; then
    command smartcat "$@"
  else
    command cat "$@"
  fi
}
