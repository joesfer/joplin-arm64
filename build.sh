#!/usr/bin/bash

set -eu

basedir=$(readlink -f $(dirname "$0"))

# Where source files are cloned from github
repo="laurent22/joplin"
srcdir="/tmp/github_joplin"

# npm cache directory for building stage
npmcache="${srcdir}/npm-cache"

# where files are packaged
distdir=${basedir}/dist

download() {
	# fetch latest version tag
	tag=`curl -s https://api.github.com/repos/${repo}/releases/latest |
		grep '\"tag_name\"' |
		sed -E 's/.*:\s*"([^"]+)".*/\1/'`

	# clone that branch only
	echo "Cloning ${repo} ${tag} into ${srcdir}..."
	git clone -q -b ${tag} --single-branch --depth 1 https://github.com/${repo} ${srcdir}
}

build() {
	# This script is inspired by the PKGBUILD script in 
	# https://aur.archlinux.org/packages/joplin/
	cd ${srcdir}

	# Remove husky (git hooks) from dependencies
	sed -i '/"husky": ".*"/d' package.json

	# Force Lang
	# INFO: https://github.com/alfredopalhares/joplin-pkgbuild/issues/25
	export LANG=en_US.utf8

	# Modify build to remove usages of the keytar module from code, which is
	# not available for arm64 architecture
	sed -i '/"keytar": ".*"/d' CliClient/package.json
	sed -i '/"keytar": ".*"/d' ElectronClient/package.json

	# Patch ReactNative client code to remove usage of keytar. This code is
	# copied into the Cli and Electron apps as part of the joplin build
	git apply ${basedir}/keytar.patch

	# This shares an npmcache directory, and will take a *while* if compiling
	# from scratch. It also seems to be building dependencies such as sqlite3
	# several times. This can all likely be sped up significantly.

	# npm complains for missing execa package - force to install it
	npm install --cache ${npmcache} execa
	npm install --cache ${npmcache}

	# CliClient
	cd CliClient
	npm install --cache ${npmcache}
	cd ..

	# Electron App
	cd ElectronClient
	npm install --cache ${npmcache}
	npm run dist

	cd ${basedir}
}

package() {
	cd ${srcdir}
	version=`git tag | tail -c +2`
	cd ..

	dst=${distdir}/joplin-${version}
	echo "Packaging into ${dst}"

	# cli client

	librelative=lib/node_modules/joplin
	libdir=${dst}/joplin-cli/${librelative}
	mkdir -p ${libdir}
	cp -R ${srcdir}/CliClient/build/* ${libdir}
	cp -R ${srcdir}/CliClient/node_modules ${libdir}

	bindir=${dst}/joplin-cli/bin
	mkdir -p ${bindir}
	ln -s ../${librelative}/main.js ${bindir}/joplin

	# electron client
	mkdir -p ${dst}/joplin
	cp -R ${srcdir}/ElectronClient/dist/*.AppImage ${dst}/joplin

	cd ${basedir}
}

cleanup() {
	echo "Cleaning up..."
	rm -rf ${srcdir}
}

# Download sources
download

# Expand sources and compile code
build

# Package up dist files
package

# cleanup sources
cleanup

echo "Process terminated successfully. Results in ${distdir}"
