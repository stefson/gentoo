# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517="setuptools"
PYTHON_COMPAT=( python3_{11..13} )

inherit distutils-r1

DESCRIPTION="A lightweight, object-oriented state machine implementation in Python"
HOMEPAGE="https://github.com/pytransitions/transitions"
SRC_URI="
	https://github.com/pytransitions/${PN}/archive/${PV}.tar.gz
		-> ${P}.gh.tar.gz
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 ~arm64 x86"
IUSE="examples"

RDEPEND="
	|| (
		dev-python/pygraphviz[${PYTHON_USEDEP}]
		dev-python/graphviz[${PYTHON_USEDEP}]
	)
	dev-python/six[${PYTHON_USEDEP}]
"
BDEPEND="
	test? (
		dev-python/dill[${PYTHON_USEDEP}]
		dev-python/mock[${PYTHON_USEDEP}]
	)
"

EPYTEST_IGNORE=(
	# pycodestyle, mypy, etc.
	tests/test_codestyle.py
)
EPYTEST_PLUGINS=()
distutils_enable_tests pytest

src_install() {
	distutils-r1_src_install
	use examples && dodoc examples/*.ipynb
}
