# Colored log function
# v0.1
# TODO: Use env var to set log level
function log {
  if [[ "$1" =~ ^(info|warn|error|debug)$ ]]; then
    level="$1"
    shift
  else
    level="info"
  fi
  # xterm256 color codes
  case "$level" in
    debug) color=152 ;;
    info)  color=69 ;;
    warn)  color=178 ;;
    error) color=124 ;;
    *)     color="$(tput sgr0)" ;;
  esac
  color="\\u001b[38;5;${color}m"
  printf "$(tput bold)[${color}${level^^}$(tput sgr0)$(tput bold)] $(basename $0):$(tput sgr0)${color} $*$(tput sgr0)\n" 1>&2
}
