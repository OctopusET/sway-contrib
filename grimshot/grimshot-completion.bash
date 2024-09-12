#!/bin/bash

# To make use of this script simply add: source path/to/grimshot-completion.bash
# to your .bashrc.

_grimshot_bash_comp() {
    local req_target="copy save savecopy"
    local first_char=$(cut -c -1 <<< "${COMP_WORDS[1]}")

    local target_pos=3
    local cmd_index=1
    local cmd_pos=2 
    if [[ $first_char == "-" ]]; then
        target_pos=4
        cmd_index=2
        cmd_pos=3
    fi

    # Complete options
    if [[ $first_char == "-" && ${#COMP_WORDS[@]} -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "--notify --cursor --wait" -- "${COMP_WORDS[COMP_CWORD]}") )

    # Complete commands
    elif [[ ${#COMP_WORDS[@]} -eq $cmd_pos ]]; then
        COMPREPLY=( $(compgen -W "check usage $req_target" -- "${COMP_WORDS[COMP_CWORD]}") )

    # Complete targets
    elif [[ $req_target =~ "${COMP_WORDS[$cmd_index]}" && ${#COMP_WORDS[@]} -eq $target_pos ]]; then
        COMPREPLY=( $(compgen -W "active screen output area window anything" -- "${COMP_WORDS[COMP_CWORD]}") )
    fi
}

complete -F _grimshot_bash_comp grimshot
