_grimpicker() {
	local cur="${COMP_WORDS[COMP_CWORD]}"

	short=(-p -d -e -c -n -h -v)
	long=(--print --draw --escape --copy --notify --help --version)

	if [[ $cur == --* ]]; then
		COMPREPLY=($(compgen -W "${long[*]}" -- "$cur"))
	else
		COMPREPLY=($(compgen -W "${short[*]}" -- "$cur"))
		COMPREPLY+=($(compgen -W "${long[*]}" -- "$cur"))
	fi
}

complete -F _grimpicker grimpicker
