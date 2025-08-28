# Reusable option parsing, maps to bash-compatible form e.g. --my-option => MY_OPTION
declare -a options=(arg-one arg-two)
for (( i=1; i <= $#; i++ )); do
  arg=${!i}
  for option in ${options[@]}; do
    option_var="${option//-/_}"
    option_var="${option_var^^}"
    if [[ $arg == --${option}=* ]]; then
      export ${option_var}=${arg#--$option=}
      break
    elif [[ $arg == --$option ]]; then
      next_arg_index=$((i+1))
      (( i < $# )) && export ${option_var}=${!next_arg_index}
      break
    fi
  done
done
