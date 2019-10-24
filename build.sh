#!/bin/bash
set -euo pipefail

node_sass_version="4.13.0"
image_name="node-sass-alpine-builder"
default_node_versions="6 8 10 11 12 13"

set -- ${1-${default_node_versions}}
for node_major_version
do
	case "${node_major_version}" in
	6|8|10|11|12|13)
		;;
	*)
		echo >&2 "Node version \"${node_major_version}\" not supported"
		exit 1
		;;
	esac
done

checkout_source() {
	local node_sass_tag="v${1?need node sass version}"
	echo "Checking out node-sass ${node_sass_tag}"
	[[ -d node-sass/.git ]] || git clone https://github.com/sass/node-sass --recursive
	(
	cd node-sass
	rm -rf vendor/
	git clean -f -d
	git checkout "${node_sass_tag}"
	git submodule update --init --recursive
	)
}

dockerfile() {
	local base_image_name="$1"
	local file="$2"

	echo "Generating $file"
	cat <<- EOF > $file
	FROM ${base_image_name}
	ARG NODE_SASS_VERSION
	RUN apk add --no-cache 'python<3' git-perl bash make gcc g++
	RUN rm /bin/sh && ln -s /bin/bash /bin/sh
	WORKDIR /node-sass
	COPY ./node-sass/package.json /node-sass/package.json
	RUN npm install --verbose
	COPY ./node-sass /node-sass/
	EOF
}

build_docker_image() {
	base_image_name="node:${major_node_version?need major node version}-alpine"
	dockerfile "${base_image_name}" "Dockerfile.${docker_image_name?need docker image name}"
	echo "Preparing Docker image \"${docker_image_name}\" based on \"${base_image_name}\""
	docker build --tag "${docker_image_name}" -f "Dockerfile.${docker_image_name}" \
		--build-arg NODE_SASS_VERSION=${node_sass_version} .
	rm "Dockerfile.${docker_image_name}"
}

inside_node_version() {
	if ! running_node_version=$(docker run --rm "${docker_image_name}" node --version) ; then
		echo "failed to get node version"
		exit 1
	fi
}

run_inside_container() {
	local volumes=(
		"$PWD/node-sass:/node-sass:Z"
		"/node-sass/node_modules"
		"$PWD/dist/${running_node_version?need running node version}:/dist:Z"
	)
	docker run \
		${volumes[@]/#/-v } \
		-it --rm "${docker_image_name?need docker image name}" "$@"
}

build_node_sass() {
	inside_node_version
	echo "Building node-sass ${node_sass_version} for node ${running_node_version} using \"${docker_image_name}\""
	run_inside_container bash -c "node scripts/build.js -f --verbose && cp -a vendor/* /dist"
}

rename_dist_files() {
	find dist -type f -name 'binding.node' | while read FILE ; do
		mv "${FILE}" $(sed -e 's#linux-x64#linux_musl-x64#' <<< "$FILE" | sed -e 's#/binding#_binding#')
		rmdir $(dirname $FILE)
	done
}

## Main
## ----------------

## Output format should be like
# * dist/v4.0.0
# * dist/v4.0.0/linux_musl-x64-42_binding.node

checkout_source "${node_sass_version}"
for major_node_version
do
	docker_image_name="${image_name}:${major_node_version}"
	build_docker_image "${major_node_version}"
	build_node_sass
done

rename_dist_files
