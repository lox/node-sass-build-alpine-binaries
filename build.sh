#!/bin/bash
set -euo pipefail

node_sass_version=4.13.0
node_versions=( 6 8 10 11 12 13 )
image_name=node-sass-alpine-builder

checkout_source() {
	local version="$1"
	echo "Checking out node-sass v${version}"
	[[ -d node-sass/.git ]] || git clone https://github.com/sass/node-sass --recursive
	(
	cd node-sass
	rm -rf vendor/
	git clean -f -d
	git checkout "v$version"
	git submodule update --init --recursive
	)
}

dockerfile() {
	local version="$1"
	local file="$2"

	echo "Generating $file"
	cat <<- EOF > $file
	FROM node:${version}-alpine
	ARG NODE_SASS_VERSION
	RUN apk add --no-cache python=2.7.14-r0 git-perl bash make gcc g++
	RUN rm /bin/sh && ln -s /bin/bash /bin/sh
	WORKDIR /node-sass
	COPY ./node-sass/package.json /node-sass/package.json
	RUN npm install --verbose
	COPY ./node-sass /node-sass/
	EOF
}

build_docker_image() {
	local version="$1"
	dockerfile "$version" "Dockerfile.${version}"
	echo "Building $image_name:${version}"
	docker build --tag "$image_name:${version}" -f "Dockerfile.${version}" \
		--build-arg NODE_SASS_VERSION=${node_sass_version} .
	rm "Dockerfile.${version}"
}

build_node_sass() {
	local version="$1"
	local exact_version
	if ! exact_version=$(docker run --rm "$image_name:${version}" node --version) ; then
		echo "failed to get node version"
		exit 1
	fi
	local volumes=(
		"$PWD/node-sass:/node-sass"
		"/node-sass/node_modules"
		"$PWD/build/${exact_version}:/build"
	)
	echo "Building node $exact_version"
	docker run \
		${volumes[@]/#/-v } \
		-it --rm "$image_name:${version}" \
			bash -c "node scripts/build.js -f --verbose && cp -a vendor/* /build"
}

rename_build_files() {
	find build -type f -name 'binding.node' | while read FILE ; do
		mv "${FILE}" $(sed -e 's#linux-x64#linux_musl-x64#' <<< "$FILE" | sed -e 's#/binding#_binding#')
		rmdir $(dirname $FILE)
	done
}

## Main
## ----------------

## Output format should be like
# * build/v4.0.0
# * build/v4.0.0/linux_musl-x64-42_binding.node

checkout_source "$node_sass_version"

for version in "${node_versions[@]}" ; do
	build_docker_image "$version"
	build_node_sass "$version"
done

rename_build_files
