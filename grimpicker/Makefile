PKGNAME = "grimpicker"
DESTDIR ?= ""
PREFIX ?= "/usr"

.PHONY: build install

build:
	scdoc <"${PKGNAME}.1.scd" >"${PKGNAME}.1"

install:
	# Not installing zsh completion here as its destination depends on the distribution
	install -D -m 755 "${PKGNAME}" "${DESTDIR}${PREFIX}/bin/${PKGNAME}"
	install -D -m 644 "completion.bash" "${DESTDIR}${PREFIX}/share/bash-completion/completions/${PKGNAME}"
	install -D -m 644 "completion.fish" "${DESTDIR}${PREFIX}/share/fish/vendor_completions.d/${PKGNAME}.fish"
	install -D -m 644 "${PKGNAME}.1" "${DESTDIR}${PREFIX}/share/man/man1/${PKGNAME}.1"
