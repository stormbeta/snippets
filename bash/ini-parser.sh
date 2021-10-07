#!/usr/bin/env bash

# Modified version of https://stackoverflow.com/a/6318901
# Original did not handle spaces or brace escapes correctly
function cfg_parser {
    ini="$(<$1)"                # read the file
    ini="${ini//[/\\[}"          # escape [
    ini="${ini//]/\\]}"          # escape ]
    IFS=$'\n' && ini=( ${ini} ) # convert to line-array
    ini=( ${ini[*]//;*/} )      # remove comments with ;
    ini=( ${ini[*]/\ *=/=} )  # remove tabs before =
    ini=( ${ini[*]/=\   /=} )   # remove tabs after =
    ini=( ${ini[*]/\ =\ /=} )   # remove anything with a space around =
    ini=( ${ini[*]/#\\[/\}$'\n'cfg.section.} ) # set section prefix
    ini=( ${ini[*]/%\\]/ \(} )    # convert text2function (1)
    ini=( ${ini[*]/=/=\( } )    # convert item to array
    ini=( ${ini[*]/%/ \)} )     # close array parenthesis
    ini=( ${ini[*]/%\\ \)/ \\} ) # the multiline trick
    ini=( ${ini[*]/%\( \)/\(\) \{} ) # convert text2function (2)
    ini=( ${ini[*]/%\} \)/\}} ) # remove extra parenthesis
    ini[0]="" # remove first element
    ini[${#ini[*]} + 1]='}'    # add the last brace
    eval "$(echo "${ini[*]}")" # eval the result
}

# TODO: add examples of usage
# example usage
#for section in $(declare -F | cut -d' ' -f 3- | grep -P '^cfg\.section\..+'); do
  #$section
  #if [[ "$<FIELD>" == "<VALUE>" ]]; then
    #export SOME_VAR="$(sed -r 's/^cfg\.section\.//' <<< "$section")"
    #export ANOTHER_VAR="$<SOME_OTHER_FIELD>"
  #fi
#done
