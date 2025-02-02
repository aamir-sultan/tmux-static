#!/usr/bin/env bash

set -o errexit

declare -A version

version[musl]=1.2.4
version[libevent]=2.1.12
version[ncurses]=6.4
version[tmux]=3.4

targetdir=$1
if [[ ${targetdir} == "" ]]; then
	targetdir=${PWD}/out
fi
mkdir -p "${targetdir}"

jobs=$(($(nproc) + 1))
CC=("${targetdir}/bin/musl-gcc" -static)
_CFLAGS=(-Os -ffunction-sections -fdata-sections)
if "${REALGCC:-gcc}" -v 2>&1 | grep -q -- --enable-default-pie; then
	_CFLAGS+=(-no-pie)
fi
_LDFLAGS=("-Wl,--gc-sections" -flto)

_musl() {
	if [[ ! -e musl-${version[musl]}.tar.gz ]]; then
		curl -LO "https://www.musl-libc.org/releases/musl-${version[musl]}.tar.gz"
	fi
	tar zxf "musl-${version[musl]}.tar.gz" --skip-old-files
	pushd .
	cd "musl-${version[musl]}"
	CFLAGS="${_CFLAGS[*]}" LDFLAGS="${_LDFLAGS[*]}" ./configure --prefix="${targetdir}" --disable-shared
	make -j $jobs
	make install
	make clean
	popd
}

_libevent() {
	if [[ ! -e libevent-${version[libevent]}-stable.tar.gz ]]; then
		curl -LO "https://github.com/libevent/libevent/releases/download/release-${version[libevent]}-stable/libevent-${version[libevent]}-stable.tar.gz"
	fi
	tar zxf "libevent-${version[libevent]}-stable.tar.gz" --skip-old-files
	pushd .
	cd "libevent-${version[libevent]}-stable"
	_cflags=("${_CFLAGS[@]}" -flto -fno-lto)
	CC="${CC[*]}" CFLAGS="${_cflags[*]}" LDFLAGS="${_LDFLAGS[*]}" ./configure --prefix="${targetdir}" --disable-shared --disable-openssl
	make -j $jobs
	make install
	make clean
	popd
}

_ncurses() {
	if [[ ! -e ncurses-${version[ncurses]}.tar.gz ]]; then
		curl -LO "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${version[ncurses]}.tar.gz"
	fi
	tar zxf "ncurses-${version[ncurses]}.tar.gz" --skip-old-files
	pushd .
	cd "ncurses-${version[ncurses]}"

	_cflags=("${_CFLAGS[@]}" -flto -fno-lto)
	CC="${CC[*]}" CFLAGS="${_cflags[*]}" LDFLAGS="${_LDFLAGS[*]}" ./configure --prefix "$targetdir" \
		--with-default-terminfo-dir=/usr/share/terminfo \
		--with-terminfo-dirs="/etc/terminfo:/lib/terminfo:/usr/share/terminfo" \
		--enable-pc-files \
		--with-pkg-config-libdir="${targetdir}/lib/pkgconfig" \
		--without-ada \
		--without-debug \
		--with-termlib \
		--without-cxx \
		--without-progs \
		--without-manpages \
		--disable-db-install \
		--without-tests
	make -j $jobs
	make install
	make clean
	popd
}

_tmux() {
	if [[ ! -e tmux-${version[tmux]}.tar.gz ]]; then
		curl -LO "https://github.com/tmux/tmux/releases/download/${version[tmux]}/tmux-${version[tmux]}.tar.gz"
	fi
	tar zxf "tmux-${version[tmux]}.tar.gz" --skip-old-files
	pushd .
	cd "tmux-${version[tmux]}"
	_cflags=("${_CFLAGS[@]}" -flto "-I${targetdir}/include/ncurses/")
	CC="${CC[*]}" CFLAGS="${_cflags[*]}" LDFLAGS="${_LDFLAGS[*]}" PKG_CONFIG_PATH="${targetdir}/lib/pkgconfig" ./configure --enable-static --prefix="${targetdir}"
	make -j $jobs
	make install
	make clean
	popd

	cp "${targetdir}/bin/tmux" .
	strip --strip-all ./tmux
	if command -v upx &>/dev/null; then
		upx -k --best ./tmux
	fi
}

rm -rf "${targetdir}/out"

if [[ ! -x "${targetdir}/bin/musl-gcc" ]]; then
	_musl
fi

_cleanup(){
	rm -rf tmux-${version[tmux]}* ncurses-${version[ncurses]}* libevent-${version[libevent]}-stable* musl-${version[musl]}* ${targetdir}
}

_libevent
_ncurses
_tmux
_cleanup