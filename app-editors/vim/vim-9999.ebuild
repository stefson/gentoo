# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Please bump with app-editors/vim-core and app-editors/gvim

VIM_VERSION="9.1"
VIM_PATCHES_VERSION="9.0.2092"

LUA_COMPAT=( lua5-{1..4} luajit )
PYTHON_COMPAT=( python3_{11..14} )
PYTHON_REQ_USE="threads(+)"
USE_RUBY="ruby31 ruby32"

inherit bash-completion-r1 flag-o-matic lua-single desktop python-single-r1 ruby-single toolchain-funcs vim-doc xdg-utils

if [[ ${PV} == 9999* ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/vim/vim.git"
else
	SRC_URI="https://github.com/vim/vim/archive/v${PV}.tar.gz -> ${P}.tar.gz
		https://git.sr.ht/~xxc3nsoredxx/vim-patches/refs/download/vim-${VIM_PATCHES_VERSION}-patches/vim-${VIM_PATCHES_VERSION}-patches.tar.xz"
	KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86 ~amd64-linux ~x86-linux ~arm64-macos ~ppc-macos ~x64-macos ~x64-solaris"
fi

DESCRIPTION="Vim, an improved vi-style text editor"
HOMEPAGE="https://www.vim.org https://github.com/vim/vim"

LICENSE="vim"
SLOT="0"
IUSE="acl crypt cscope debug gpm lua minimal nls perl python racket ruby selinux sound tcl terminal vim-pager X"
REQUIRED_USE="
	lua? ( ${LUA_REQUIRED_USE} )
	python? ( ${PYTHON_REQUIRED_USE} )
	vim-pager? ( !minimal )
"

RDEPEND="
	~app-editors/vim-core-${PV}
	>=app-eselect/eselect-vi-1.1
	>=sys-libs/ncurses-5.2-r2:0=
	acl? ( kernel_linux? ( sys-apps/acl ) )
	crypt? ( dev-libs/libsodium:= )
	cscope? ( dev-util/cscope )
	gpm? ( >=sys-libs/gpm-1.19.3 )
	lua? (
		${LUA_DEPS}
		$(lua_gen_impl_dep 'deprecated' lua5-1)
	)
	nls? ( virtual/libintl )
	perl? ( dev-lang/perl:= )
	python? ( ${PYTHON_DEPS} )
	racket? ( dev-scheme/racket )
	ruby? ( ${RUBY_DEPS} )
	selinux? ( sys-libs/libselinux )
	sound? ( media-libs/libcanberra )
	tcl? ( dev-lang/tcl:0= )
	vim-pager? ( app-editors/vim-core[-minimal] )
	X? ( x11-libs/libXt )
"
DEPEND="${RDEPEND}
	X? ( x11-base/xorg-proto )
"
# configure runs the Lua interpreter
BDEPEND="
	dev-build/autoconf
	lua? ( ${LUA_DEPS} )
	nls? ( sys-devel/gettext )
"
PDEPEND="!minimal? ( app-vim/gentoo-syntax )"

if [[ ${PV} != 9999* ]]; then
	# Gentoo patches to fix runtime issues, cross-compile errors, etc
	PATCHES=(
		"${WORKDIR}/vim-${VIM_PATCHES_VERSION}-patches"
	)
fi

# platform-specific checks (bug #898450 #898452):
# - acl()     -- Solaris
# - statacl() -- AIX
QA_CONFIG_IMPL_DECL_SKIP=(
	'acl'
	'statacl'
)

pkg_setup() {
	# people with broken alphabets run into trouble. bug #82186.
	unset LANG LC_ALL
	export LC_COLLATE="C"

	use lua && lua-single_pkg_setup
	use python && python-single-r1_pkg_setup
}

src_prepare() {
	default

	# Fixup a script to use awk instead of nawk
	sed -i -e \
		'1s|.*|#!'"${EPREFIX}"'/usr/bin/awk -f|' \
		"${S}"/runtime/tools/mve.awk || die "mve.awk sed failed"

	# Read vimrc and gvimrc from /etc/vim
	echo '#define SYS_VIMRC_FILE "'${EPREFIX}'/etc/vim/vimrc"' \
		>> "${S}"/src/feature.h || die "echo failed"
	echo '#define SYS_GVIMRC_FILE "'${EPREFIX}'/etc/vim/gvimrc"' \
		>> "${S}"/src/feature.h || die "echo failed"

	# Use exuberant ctags which installs as /usr/bin/exuberant-ctags.
	# Hopefully this pattern won't break for a while at least.
	# This fixes bug #29398 (27 Sep 2003 agriffis)
	sed -i -e \
		's/\<ctags\("\| [-*.]\)/exuberant-&/g' \
		"${S}"/runtime/doc/syntax.txt \
		"${S}"/runtime/doc/tagsrch.txt \
		"${S}"/runtime/doc/usr_29.txt \
		"${S}"/runtime/menu.vim \
		"${S}"/src/configure.ac || die 'sed failed'

	# gcc on sparc32 has this, uhm, interesting problem with detecting EOF
	# correctly. To avoid some really entertaining error messages about stuff
	# which isn't even in the source file being invalid, we'll do some trickery
	# to make the error never occur. bug 66162 (02 October 2004 ciaranm)
	find "${S}" -name '*.c' | while read c; do
		echo >> "$c" || die "echo failed"
	done

	# conditionally make the manpager.sh script
	if use vim-pager; then
		cat > "${S}"/runtime/macros/manpager.sh <<-_EOF_ || die "cat EOF failed"
			#!/bin/sh
			sed -e 's/\x1B\[[[:digit:]]\+m//g' | col -b | \\
					vim \\
						-c 'let no_plugin_maps = 1' \\
						-c 'set nolist nomod ft=man ts=8' \\
						-c 'let g:showmarks_enable=0' \\
						-c 'runtime! macros/less.vim' -
			_EOF_
	fi

	# Try to avoid sandbox problems. Bug #114475.
	if [[ -d "${S}"/src/po ]]; then
		sed -i -e \
			'/-S check.vim/s,..VIM.,ln -s $(VIM) testvim \; ./testvim -X,' \
			"${S}"/src/po/Makefile || die "sed failed"
	fi

	cp -v "${S}"/src/config.mk.dist "${S}"/src/auto/config.mk || die "cp failed"

	# Fix bug 18245: Prevent "make" from the following chain:
	# (1) Notice configure.ac is newer than auto/configure
	# (2) Rebuild auto/configure
	# (3) Notice auto/configure is newer than auto/config.mk
	# (4) Run ./configure (with wrong args) to remake auto/config.mk
	sed -i -e \
		's# auto/config\.mk:#:#' src/Makefile || die "Makefile sed failed"
	rm src/auto/configure || die "rm failed"

	# --with-features=huge forces on cscope even if we --disable it. We need
	# to sed this out to avoid screwiness. (1 Sep 2004 ciaranm)
	if ! use cscope; then
		sed -i -e \
			'/# define FEAT_CSCOPE/d' src/feature.h || die "couldn't disable cscope"
	fi

	# bug 908961
	if use elibc_musl ; then
		sed -i -e '/ja.sjis/d' src/po/Make_all.mak || die
	fi
}

src_configure() {
	emake -j1 -C src autoconf

	# This should fix a sandbox violation (see bug #24447). The hvc
	# things are for ppc64, see bug #86433.
	local file
	for file in /dev/pty/s* /dev/console /dev/hvc/* /dev/hvc*; do
		if [[ -e ${file} ]]; then
			addwrite ${file}
		fi
	done

	local myconf=(
		--with-modified-by="Gentoo-${PVR} (RIP Bram)"
		--enable-gui=no
		--disable-darwin
	)

	if use minimal; then
		myconf+=(
			--with-features=tiny
			--disable-nls
			--disable-canberra
			--disable-acl
			--without-x
			--disable-luainterp
			--disable-perlinterp
			--disable-pythoninterp
			--disable-mzschemeinterp
			--disable-rubyinterp
			--disable-selinux
			--disable-tclinterp
			--disable-gpm
		)
	else
		use debug && append-flags "-DDEBUG"

		myconf+=(
			--with-features=huge
			$(use_enable sound canberra)
			$(use_enable acl)
			$(use_enable crypt libsodium)
			$(use_enable cscope)
			$(use_enable gpm)
			$(use_enable nls)
			$(use_enable perl perlinterp)
			$(use_enable python python3interp)
			$(use_with python python3-command "${PYTHON}")
			$(use_enable racket mzschemeinterp)
			$(use_enable ruby rubyinterp)
			$(use_enable selinux)
			$(use_enable tcl tclinterp)
			$(use_enable terminal)
		)

		if use lua; then
			# -DLUA_COMPAT_OPENLIB=1 is required to enable the
			# deprecated (in 5.1) luaL_openlib API (#874690)
			use lua_single_target_lua5-1 && append-cppflags -DLUA_COMPAT_OPENLIB=1

			myconf+=(
				--enable-luainterp
				$(use_with lua_single_target_luajit luajit)
				--with-lua-prefix="${EPREFIX}/usr"
			)
		fi

		# don't test USE=X here ... see bug #19115
		# but need to provide a way to link against X ... see bug #20093
		myconf+=(
			$(use_with X x)
		)
	fi

	# let package manager strip binaries
	export ac_cv_prog_STRIP="$(type -P true ) faking strip"

	# keep prefix env contained within the EPREFIX
	use prefix && myconf+=( --without-local-dir )

	if tc-is-cross-compiler ; then
		export vim_cv_getcwd_broken=no \
			   vim_cv_memmove_handles_overlap=yes \
			   vim_cv_stat_ignores_slash=yes \
			   vim_cv_terminfo=yes \
			   vim_cv_toupper_broken=no
	fi

	econf "${myconf[@]}"
}

src_compile() {
	# The following allows emake to be used
	emake -j1 -C src auto/osdef.h objects

	emake
}

src_test() {
	einfo
	einfo "Starting vim tests. Several error messages will be shown"
	einfo "while the tests run. This is normal behaviour and does not"
	einfo "indicate a fault."
	einfo
	ewarn "If the tests fail, your terminal may be left in a strange"
	ewarn "state. Usually, running 'reset' will fix this."
	einfo

	# Don't let vim talk to X
	unset DISPLAY

	# Arch and opensuse seem to do this and at this point, I'm willing
	# to try anything to avoid random test hangs!
	export TERM=xterm

	# See https://github.com/vim/vim/blob/f08b0eb8691ff09f98bc4beef986ece1c521655f/src/testdir/runtest.vim#L5
	# for more information on test variables we can use.
	# Note that certain variables need vim-compatible regex (not PCRE), see e.g.
	# http://www.softpanorama.org/Editors/Vimorama/vim_regular_expressions.shtml.
	#
	# Skipped tests:
	# - Test_expand_star_star
	# Hangs because of a recursive symlink in /usr/include/nodejs (bug #616680)
	# - Test_exrc
	# Looks in wrong location? (bug #742710)
	# - Test_job_tty_in_out
	# Fragile and depends on TERM(?)
	# - Test_spelldump_bang
	# Hangs.
	# - Test_fuzzy_completion_env
	# Too sensitive to leaked environment variables.
	# - Test_term_mouse_multiple_clicks_to_select_mode
	# Hangs.
	# - Test_spelldump
	# Hangs.
	# - Test_glvs_*
	# Depends on local network.
	export TEST_SKIP_PAT='\(Test_expand_star_star\|Test_exrc\|Test_job_tty_in_out\|Test_spelldump_bang\|Test_fuzzy_completion_env\|Test_term_mouse_multiple_clicks_to_select_mode\|Test_spelldump\|Test_glvs_\)'

	# Don't do additional GUI tests.
	emake -j1 -C src/testdir nongui
}

# Call eselect vi update with --if-unset
# to respect user's choice (bug #187449)
eselect_vi_update() {
	ebegin "Calling eselect vi update"
	eselect vi update --if-unset
	eend $?
}

src_install() {
	local vimfiles=/usr/share/vim/vim${VIM_VERSION/.}

	# Note: Do not install symlinks for 'vi', 'ex', or 'view', as these are
	#       managed by eselect-vi
	dobin src/vim
	if ! use minimal ; then
		dosym vim /usr/bin/vimdiff
	fi
	dosym vim /usr/bin/rvim
	dosym vim /usr/bin/rview
	if use vim-pager ; then
		dosym ${vimfiles}/macros/less.sh /usr/bin/vimpager
		dosym ${vimfiles}/macros/manpager.sh /usr/bin/vimmanpager
		insinto ${vimfiles}/macros
		doins runtime/macros/manpager.sh
		fperms a+x ${vimfiles}/macros/manpager.sh
	fi

	domenu runtime/vim.desktop

	newbashcomp "${FILESDIR}"/${PN}-completion ${PN}

	# keep in sync with 'complete ... -F' list
	bashcomp_alias vim ex vi view rvim rview vimdiff
}

pkg_postinst() {
	# update documentation tags (from vim-doc.eclass)
	update_vim_helptags

	# update desktop file mime cache
	xdg_desktop_database_update

	# call eselect vi update
	eselect_vi_update
}

pkg_postrm() {
	# update documentation tags (from vim-doc.eclass)
	update_vim_helptags

	# update desktop file mime cache
	xdg_desktop_database_update

	# call eselect vi update
	eselect_vi_update
}
