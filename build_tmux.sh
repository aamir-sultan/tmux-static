#!/usr/bin/env bash 

set -o errexit

declare -A version

version[m4]=1.4.19
version[bison]=3.8.2
version[ncurses]=6.4
version[musl]=1.2.4
version[libevent]=2.1.12
version[tmux]=3.5a

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

# PATH=$PATH:${targetdir}/bin

# Function to install m4 locally
_m4() {
    if [[ ! -e m4-${version[m4]}.tar.gz ]]; then
        curl -LO "https://ftp.gnu.org/gnu/m4/m4-${version[m4]}.tar.gz"
    fi
    tar zxf "m4-${version[m4]}.tar.gz" --skip-old-files
    pushd .
    cd "m4-${version[m4]}"
    CFLAGS="-Os -ffunction-sections -fdata-sections" LDFLAGS="-Wl,--gc-sections" ./configure --prefix="${targetdir}"
    make -j $jobs
    make install
    make clean
    popd
}

# Function to install ncurses locally
_ncurses() {
    if [[ ! -e ncurses-${version[ncurses]}.tar.gz ]]; then
        curl -LO "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${version[ncurses]}.tar.gz"
    fi
    tar zxf "ncurses-${version[ncurses]}.tar.gz" --skip-old-files
    pushd .
    cd "ncurses-${version[ncurses]}"

    CFLAGS="-Os -ffunction-sections -fdata-sections" LDFLAGS="-Wl,--gc-sections" \
    ./configure --prefix "$targetdir" \
        --with-default-terminfo-dir=/usr/share/terminfo \
        --with-terminfo-dirs="/etc/terminfo:/lib/terminfo:/usr/share/terminfo" \
        --enable-pc-files \
        --without-ada \
        --without-debug \
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


# Function to install bison (which includes yacc) locally
_bison() {
    if [[ ! -e bison-${version[bison]}.tar.gz ]]; then
        curl -LO "https://ftp.gnu.org/gnu/bison/bison-${version[bison]}.tar.gz"
    fi
    tar zxf "bison-${version[bison]}.tar.gz" --skip-old-files
    pushd .
    cd "bison-${version[bison]}"

    # Set LDFLAGS and CPPFLAGS to ensure it links to local ncurses
    LDFLAGS="-L${targetdir}/lib" CPPFLAGS="-I${targetdir}/include" ./configure --prefix="${targetdir}" --disable-nls --without-gettext
    make -j $jobs
    make install
    make clean
    popd
}

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

# Step 4: Clean up the source directories
_cleanup() {
    rm -rf bison-${version[bison]}* 
    rm -rf ncurses-${version[ncurses]}* 
    rm -rf m4-${version[m4]}* 
    rm -rf tmux-${version[tmux]}* 
    rm -rf libevent-${version[libevent]}-stable* 
    rm -rf musl-${version[musl]}* 
    rm -rf ${targetdir}
}

# Remove any existing installation
rm -rf "${targetdir}/out"
_cleanup


# Step 1: Install m4 locally if it's not already installed
if [[ ! -e "${targetdir}/bin/m4" ]]; then
    _m4
fi

# Step 2: Install ncurses locally if it's not already installed
if [[ ! -e "${targetdir}/bin/ncurses-config" ]]; then
    _ncurses
fi

# Step 3: Install bison locally if it's not already installed
if [[ ! -e "${targetdir}/bin/yacc" ]]; then
    _bison
fi

# Step 4: Install bison locally if it's not already installed
if [[ ! -e "${targetdir}/bin/musl-gcc" ]]; then
    _musl
fi

_libevent
_tmux
_cleanup

echo "Installation complete."
