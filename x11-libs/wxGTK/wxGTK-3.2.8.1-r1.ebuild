# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit edo multilib-minimal flag-o-matic toolchain-funcs

# Make sure that this matches the number of components in ${PV}
WXRELEASE="$(ver_cut 1-2)-gtk3"			# 3.2-gtk3

DESCRIPTION="GTK version of wxWidgets, a cross-platform C++ GUI toolkit"
HOMEPAGE="https://wxwidgets.org/"
SRC_URI="
	https://github.com/wxWidgets/wxWidgets/releases/download/v${PV}/wxWidgets-${PV}.tar.bz2
	doc? ( https://github.com/wxWidgets/wxWidgets/releases/download/v${PV}/wxWidgets-${PV}-docs-html.tar.bz2 )"
S="${WORKDIR}/wxWidgets-${PV}"

LICENSE="wxWinLL-3 GPL-2 doc? ( wxWinFDL-3 )"
SLOT="${WXRELEASE}/3.2"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ~ppc64 ~riscv ~sparc ~x86 ~amd64-linux ~x86-linux"
IUSE="+X curl doc debug keyring gstreamer libnotify +lzma opengl pch sdl +spell test tiff wayland webkit X"
REQUIRED_USE="test? ( tiff ) tiff? ( X ) spell? ( X ) keyring? ( X )"
RESTRICT="!test? ( test )"

RDEPEND="
	>=app-eselect/eselect-wxwidgets-20131230
	dev-libs/expat[${MULTILIB_USEDEP}]
	dev-libs/libpcre2[pcre16,pcre32,unicode]
	sdl? ( media-libs/libsdl2[${MULTILIB_USEDEP}] )
	curl? ( net-misc/curl )
	lzma? ( app-arch/xz-utils )
	X? (
		>=dev-libs/glib-2.22:2[${MULTILIB_USEDEP}]
		media-libs/libjpeg-turbo:=[${MULTILIB_USEDEP}]
		media-libs/libpng:0=[${MULTILIB_USEDEP}]
		sys-libs/zlib[${MULTILIB_USEDEP}]
		x11-libs/cairo[${MULTILIB_USEDEP}]
		>=x11-libs/gtk+-3.24.41-r1:3[wayland?,X?,${MULTILIB_USEDEP}]
		x11-libs/gdk-pixbuf:2[${MULTILIB_USEDEP}]
		x11-libs/libSM[${MULTILIB_USEDEP}]
		x11-libs/libX11[${MULTILIB_USEDEP}]
		x11-libs/libXtst
		x11-libs/libXxf86vm[${MULTILIB_USEDEP}]
		media-libs/fontconfig
		x11-libs/pango[${MULTILIB_USEDEP}]
		keyring? ( app-crypt/libsecret )
		gstreamer? (
			media-libs/gstreamer:1.0[${MULTILIB_USEDEP}]
			media-libs/gst-plugins-base:1.0[${MULTILIB_USEDEP}]
			media-libs/gst-plugins-bad:1.0[${MULTILIB_USEDEP}]
		)
		libnotify? ( x11-libs/libnotify[${MULTILIB_USEDEP}] )
		opengl? (
			virtual/opengl[${MULTILIB_USEDEP}]
			wayland? ( dev-libs/wayland )
		)
		spell? ( app-text/gspell:= )
		tiff? ( media-libs/tiff:=[${MULTILIB_USEDEP}] )
		webkit? ( net-libs/webkit-gtk:4.1= )
	)"
DEPEND="${RDEPEND}
	opengl? ( virtual/glu[${MULTILIB_USEDEP}] )
	X? ( x11-base/xorg-proto )"
BDEPEND="
	test? ( >=dev-util/cppunit-1.8.0 )
	>=app-eselect/eselect-wxwidgets-20131230
	virtual/pkgconfig"

# Note about the gst-plugin-base dep: The build system queries for it,
# but doesn't link it for some reason?  Either way - probably best to
# depend on it anyway.
# Note about the wayland dep: Appears to be only required for the OpenGL
# canvas, and it seems impossible to disable the X dependency, unless
# I'm missing something.  This is an automagic header dep, though.

PATCHES=(
	"${FILESDIR}/${PN}-3.2.1-configure-tests.patch"
	"${FILESDIR}/${PN}-3.2.1-wayland-control.patch"
	"${FILESDIR}/${PN}-3.2.1-prefer-lib64-in-tests.patch"
	"${FILESDIR}/${PN}-3.2.5-dont-break-flags.patch"
	"${FILESDIR}/${P}-wayland-titlebar.patch"
)

multilib_src_configure() {
	# defang automagic dependencies, bug #927952
	use wayland || append-cflags -DGENTOO_GTK_HIDE_WAYLAND
	use X || append-cflags -DGENTOO_GTK_HIDE_X11

	# bug #952961
	tc-is-lto && filter-flags -fno-semantic-interposition

	# Workaround for bug #915154
	append-ldflags $(test-flags-CCLD -Wl,--undefined-version)

	# X independent options
	local myeconfargs=(
		--with-zlib=sys
		--with-expat=sys
		--enable-compat30
		--enable-xrc
		$(use_with sdl)
		$(use_with lzma liblzma)
		# Currently defaults to curl, could change.  Watch the VDB!
		$(use_enable curl webrequest)

		# PCHes are unstable and are disabled in-tree where possible
		# See bug #504204
		# Commits 8c4774042b7fdfb08e525d8af4b7912f26a2fdce, fb809aeadee57ffa24591e60cfb41aecd4823090
		$(use_enable pch precomp-headers)

		# Don't hard-code libdir's prefix for wx-config
		--libdir='${prefix}'/$(get_libdir)
	)

	# By default, we now build with the GLX GLCanvas because some software like
	# PrusaSlicer does not yet support EGL:
	#
	# https://github.com/prusa3d/PrusaSlicer/issues/9774 .
	#
	# A solution for this is being developed upstream:
	#
	# https://github.com/wxWidgets/wxWidgets/issues/22325 .
	#
	# Any software that needs to use OpenGL under Wayland can be patched like
	# this to run under xwayland:
	#
	# https://github.com/visualboyadvance-m/visualboyadvance-m/commit/aca206a721265366728222d025fec30ee500de82 .
	#
	# Check that the macro wxUSE_GLCANVAS_EGL is set to 1.
	#
	myeconfargs+=( "--disable-glcanvasegl" )

	# debug in >=2.9
	# there is no longer separate debug libraries (gtk2ud)
	# wxDEBUG_LEVEL=1 is the default and we will leave it enabled
	# wxDEBUG_LEVEL=2 enables assertions that have expensive runtime costs.
	# apps can disable these features by building w/ -NDEBUG or wxDEBUG_LEVEL_0.
	# http://docs.wxwidgets.org/3.0/overview_debugging.html
	# https://groups.google.com/group/wx-dev/browse_thread/thread/c3c7e78d63d7777f/05dee25410052d9c
	use debug && myeconfargs+=( --enable-debug=max )

	# wxGTK options
	#   --enable-graphics_ctx - needed for webkit, editra
	#   --without-gnomevfs - bug #203389
	use X && myeconfargs+=(
		--enable-graphics_ctx
		--with-gtkprint
		--enable-gui
		--with-gtk=3
		--with-libpng=sys
		--with-libjpeg=sys

		# Choosing to enable this unconditionally seems fair, pcre2 is
		# almost certain to be installed.
		--with-regex=sys
		--without-gnomevfs
		$(use_enable gstreamer mediactrl)
		$(multilib_native_use_enable webkit webview)
		$(use_with libnotify)
		$(use_with opengl)
		$(use_with tiff libtiff sys)
		$(use_enable keyring secretstore)
		$(use_enable spell spellcheck)
		$(use_enable test tests)
		$(use_enable wayland)
	)

	# wxBase options
	! use X && myeconfargs+=( --disable-gui )

	# wxWidgets installs a configuration file with a reference to EGREP.
	# Autoconf discovers these programs via full paths, which is
	# unnecessary and fails if a build happened on a merged-usr system
	# but is being used on a split-usr system.  Bug #927920.
	export ac_cv_path_SED="sed"
	export ac_cv_path_EGREP="grep -E"
	export ac_cv_path_EGREP_TRADITIONAL="grep -E"
	export ac_cv_path_FGREP="grep -F"
	export ac_cv_path_GREP="grep"
	export ac_cv_path_lt_DD="dd"

	ECONF_SOURCE="${S}" econf "${myeconfargs[@]}"
}

multilib_src_test() {
	pushd tests >/dev/null || die

	emake
	# TODO: Use --success for verbose logs, but it seems to change test results?
	# TODO: test_gui too with xvfb-run, as Fedora does?
	edo ./test '~[.]~[net]'

	popd >/dev/null || die
}

multilib_src_install_all() {
	cd docs || die
	dodoc changes.txt readme.txt
	newdoc base/readme.txt base_readme.txt
	newdoc gtk/readme.txt gtk_readme.txt

	use doc && HTML_DOCS=( "${WORKDIR}"/wxWidgets-${PV}-docs-html/. )
	einstalldocs

	# Unversioned links
	rm "${ED}"/usr/bin/wx-config || die
	rm "${ED}"/usr/bin/wxrc || die
	# wxwin.m4 is owned by eselect-wxwidgets
	mv "${ED}"/usr/share/aclocal/wxwin.m4 "${ED}"/usr/share/aclocal/wxwin32-gtk3.m4 || die

	# version bakefile presets
	pushd "${ED}"/usr/share/bakefile/presets >/dev/null || die
	local f
	for f in wx*; do
		mv "${f}" "${f/wx/wx32gtk3}" || die
	done
	popd >/dev/null || die
}

pkg_postinst() {
	has_version -b app-eselect/eselect-wxwidgets \
		&& eselect wxwidgets update
}

pkg_postrm() {
	has_version -b app-eselect/eselect-wxwidgets \
		&& eselect wxwidgets update
}
