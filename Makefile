GIT_COMMIT?=$(shell git rev-parse HEAD)
GIT_COMMIT_SHORT?=$(shell git rev-parse --short HEAD)
GIT_TAG?=$(shell git describe --abbrev=0 --tags 2>/dev/null || echo "v0.0.0" )
TAG?=${GIT_TAG}-${GIT_COMMIT_SHORT}
REPO?=ttl.sh/elemental-ci
IMAGE=${REPO}:${GIT_TAG}
ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
SUDO?=sudo
CLOUD_CONFIG_FILE?="iso/config"
MANIFEST_FILE?="iso/manifest.yaml"
# This are the default images already in the dockerfile but we want to be able to override them
OPERATOR_IMAGE?=quay.io/costoolkit/elemental-operator-ci:latest
REGISTER_IMAGE?=quay.io/costoolkit/elemental-register-ci:latest
SYSTEM_AGENT_IMAGE?=rancher/system-agent:v0.2.9
BUILDER_IMAGE?=ghcr.io/rancher/elemental-toolkit/elemental-cli:v0.11.0
# Used to know if this is a release or just a normal dev build
RELEASE_TAG?=false

# Set tag based on release status for ease of use
ifeq ($(RELEASE_TAG), "true")
FINAL_TAG:=$(GIT_TAG)
else
FINAL_TAG:=$(TAG)
endif

# Set ISO variable
ARCH:=$(shell uname -m)
ISO?=elemental-teal.${ARCH}-${FINAL_TAG}.iso

.PHONY: clean
clean:
	rm -rf build

# Build elemental docker images
.PHONY: build
build:
	@DOCKER_BUILDKIT=1 docker build -f Dockerfile.image \
		--build-arg IMAGE_TAG=${FINAL_TAG} \
		--build-arg IMAGE_COMMIT=${GIT_COMMIT} \
		--build-arg IMAGE_REPO=${REPO} \
		--build-arg OPERATOR_IMAGE=${OPERATOR_IMAGE} \
		--build-arg REGISTER_IMAGE=${REGISTER_IMAGE} \
		--build-arg SYSTEM_AGENT_IMAGE=${SYSTEM_AGENT_IMAGE} \
		--build-arg BUILDER_IMAGE=${BUILDER_IMAGE} \
		-t ${REPO}:${FINAL_TAG} .
	@DOCKER_BUILDKIT=1 docker push ${REPO}:${FINAL_TAG}

.PHONY: dump_image
dump_image:
	@mkdir -p build
	@docker save ${REPO}:${FINAL_TAG} -o build/elemental-${FINAL_TAG}.tar

# Build iso with the elemental image as base
.PHONY: iso
iso:
ifeq ($(CLOUD_CONFIG_FILE),"iso/config")
	@echo "No CLOUD_CONFIG_FILE set, using the default one at ${CLOUD_CONFIG_FILE}"
else
	@cp ${CLOUD_CONFIG_FILE} iso/config
endif
ifeq ($(MANIFEST_FILE),"iso/manifest.yaml")
	@echo "No MANIFEST_FILE set, using the default one at ${MANIFEST_FILE}"
else
	@cp ${MANIFEST_FILE} iso/config
endif
	@mkdir -p build
	@DOCKER_BUILDKIT=1 docker build -f Dockerfile.iso \
		--build-arg OS_IMAGE=${REPO}:${FINAL_TAG} \
		--build-arg BUILDER_IMAGE=${BUILDER_IMAGE} \
		--build-arg VERSION=${FINAL_TAG} \
		--build-arg CLOUD_CONFIG_FILE=${CLOUD_CONFIG_FILE} \
		--build-arg MANIFEST_FILE=${MANIFEST_FILE} \
		-t iso:${FINAL_TAG} .
	@DOCKER_BUILDKIT=1 docker run --rm -v $(PWD)/build:/mnt \
		iso:${FINAL_TAG} \
		cp elemental-iso/${ISO} /mnt
	@echo "INFO: ISO available at build/${ISO}"

# Build an iso with the OBS base containers
.PHONY: remote_iso
proper_iso:
ifeq ($(CLOUD_CONFIG_FILE),"iso/config")
	@echo "No CLOUD_CONFIG_FILE set, using the default one at ${CLOUD_CONFIG_FILE}"
endif
ifeq ($(MANIFEST_FILE),"iso/manifest.yaml")
	@echo "No MANIFEST_FILE set, using the default one at ${MANIFEST_FILE}"
else
	@cp ${MANIFEST_FILE} iso/config
endif
	@mkdir -p build
	@DOCKER_BUILDKIT=1 docker build -f Dockerfile.iso \
		--build-arg CLOUD_CONFIG_FILE=${CLOUD_CONFIG_FILE} \
		--build-arg MANIFEST_FILE=${MANIFEST_FILE} \
		-t iso:latest .
	@DOCKER_BUILDKIT=1 docker run --rm -v $(PWD)/build:/mnt \
		iso:latest \
		cp elemental-iso/${ISO} /mnt
	@echo "INFO: ISO available at build/${ISO}"

.PHONY: extract_kernel_init_squash
extract_kernel_init_squash:
	@VAR='build/$(ISO)'; \
	INITRD_FILE=$$(isoinfo -R -i $${VAR} -find -type f -name initrd -print 2>/dev/null); \
	KERNEL_FILE=$$(isoinfo -R -i $${VAR} -find -type f -name kernel -print 2>/dev/null); \
	[[ -z "$${KERNEL_FILE}" ]] && KERNEL_FILE=$$(isoinfo -R -i $${VAR} -find -type f -name linux -print 2>/dev/null); \
	isoinfo -x /rootfs.squashfs -R -i $${VAR} > $${VAR/\.iso/.squashfs} 2>/dev/null; \
	isoinfo -x $${INITRD_FILE} -R -i $${VAR} > $${VAR/\.iso/-initrd} 2>/dev/null; \
	isoinfo -x $${KERNEL_FILE} -R -i $${VAR} > $${VAR/\.iso/-kernel} 2>/dev/null

.PHONY: ipxe
ipxe:
	@mkdir -p build
	@echo "#!ipxe" > build/elemental-${FINAL_TAG}.ipxe
	@echo "set arch amd64" >> build/elemental-${FINAL_TAG}.ipxe
ifeq ($(RELEASE_TAG), "true")
	@echo "set url https://github.com/rancher/elemental/releases/download/${FINAL_TAG}" >> build/elemental-${FINAL_TAG}.ipxe
else
	@echo "set url tftp://10.0.2.2/${TAG}" >> build/elemental-${FINAL_TAG}.ipxe
endif
	@echo "set kernel elemental-${FINAL_TAG}-kernel" >> build/elemental-${FINAL_TAG}.ipxe
	@echo "set initrd elemental-${FINAL_TAG}-initrd" >> build/elemental-${FINAL_TAG}.ipxe
	@echo "set rootfs elemental-${FINAL_TAG}.squashfs" >> build/elemental-${FINAL_TAG}.ipxe
	@echo "# set config http://example.com/machine-config" >> build/elemental-${FINAL_TAG}.ipxe
	@echo "# set cmdline extra.values=1" >> build/elemental-${FINAL_TAG}.ipxe
	@echo "initrd \$${url}/\$${initrd}" >> build/elemental-${FINAL_TAG}.ipxe
	@echo "chain --autofree --replace \$${url}/\$${kernel} initrd=\$${initrd} ip=dhcp rd.cos.disable root=live:\$${url}/\$${rootfs} stages.initramfs[0].commands[0]=\"curl -k \$${config} > /run/initramfs/live/livecd-cloud-config.yaml\" console=tty1 console=ttyS0 \$${cmdline}"  >> build/elemental-${FINAL_TAG}.ipxe

.PHONY: build_all
build_all: build iso extract_kernel_init_squash ipxe

.PHONY: docs
docs:
	@yarn install --frozen-lockfile
	@yarn build
