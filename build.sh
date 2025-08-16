#!/bin/bash -e

# shellcheck disable=SC2119
run_sub_stage()
{
	log "Begin ${SUB_STAGE_DIR}"
	pushd "${SUB_STAGE_DIR}" > /dev/null
	for i in {00..99}; do
		if [ -f "${i}-debconf" ]; then
			log "Begin ${SUB_STAGE_DIR}/${i}-debconf"
			on_chroot << EOF
debconf-set-selections <<SELEOF
$(cat "${i}-debconf")
SELEOF
EOF

			log "End ${SUB_STAGE_DIR}/${i}-debconf"
		fi
		if [ -f "${i}-packages-nr" ]; then
			log "Begin ${SUB_STAGE_DIR}/${i}-packages-nr"
			PACKAGES="$(sed -f "${SCRIPT_DIR}/remove-comments.sed" < "${i}-packages-nr")"
			if [ -n "$PACKAGES" ]; then
				on_chroot << EOF
apt-get -o Acquire::Retries=3 install --no-install-recommends -y $PACKAGES
EOF
			fi
			log "End ${SUB_STAGE_DIR}/${i}-packages-nr"
		fi
		if [ -f "${i}-packages" ]; then
			log "Begin ${SUB_STAGE_DIR}/${i}-packages"
			PACKAGES="$(sed -f "${SCRIPT_DIR}/remove-comments.sed" < "${i}-packages")"
			if [ -n "$PACKAGES" ]; then
				on_chroot << EOF
apt-get -o Acquire::Retries=3 install -y $PACKAGES
EOF
			fi
			log "End ${SUB_STAGE_DIR}/${i}-packages"
		fi
		if [ -d "${i}-patches" ]; then
			log "Begin ${SUB_STAGE_DIR}/${i}-patches"
			pushd "${STAGE_WORK_DIR}" > /dev/null
			if [ "${CLEAN}" = "1" ]; then
				rm -rf .pc
				rm -rf ./*-pc
			fi
			QUILT_PATCHES="${SUB_STAGE_DIR}/${i}-patches"
			SUB_STAGE_QUILT_PATCH_DIR="$(basename "$SUB_STAGE_DIR")-pc"
			mkdir -p "$SUB_STAGE_QUILT_PATCH_DIR"
			ln -snf "$SUB_STAGE_QUILT_PATCH_DIR" .pc
			quilt upgrade
			if [ -e "${SUB_STAGE_DIR}/${i}-patches/EDIT" ]; then
				echo "Dropping into bash to edit patches..."
				bash
			fi
			RC=0
			quilt push -a || RC=$?
			case "$RC" in
				0|2)
					;;
				*)
					false
					;;
			esac
			popd > /dev/null
			log "End ${SUB_STAGE_DIR}/${i}-patches"
		fi
		if [ -x ${i}-run.sh ]; then
			log "Begin ${SUB_STAGE_DIR}/${i}-run.sh"
			./${i}-run.sh
			log "End ${SUB_STAGE_DIR}/${i}-run.sh"
		fi
		if [ -f ${i}-run-chroot.sh ]; then
			log "Begin ${SUB_STAGE_DIR}/${i}-run-chroot.sh"
			on_chroot < ${i}-run-chroot.sh
			log "End ${SUB_STAGE_DIR}/${i}-run-chroot.sh"
		fi
		
	done
	
	# Copy validation files if they exist (after all steps complete)
	if [ -d "${VALIDATION_STEPS_DIR_NAME}" ] && [ -n "${FIRST_USER_NAME:-}" ]; then
		log "Copying validation files from ${SUB_STAGE_DIR}/${VALIDATION_STEPS_DIR_NAME}"
		copy_validation_files "${SUB_STAGE_DIR}" "validation" "${STAGE}"
	fi
	
	# Run build-time validations if they exist (after all steps complete)
	if [ -d "${VALIDATION_STEPS_DIR_NAME}" ]; then
		log "Running build-time validations for ${SUB_STAGE_DIR}"
		run_build_time_validations "${SUB_STAGE_DIR}"
	fi
	
	popd > /dev/null
	log "End ${SUB_STAGE_DIR}"
}

# Copy validation files from a step to the user's home directory
copy_validation_files() {
	local step_dir="$1"
	local step_name="$2"
	local stage_name="$3"
	
	# Only copy if we have a user and rootfs
	if [ -z "${FIRST_USER_NAME:-}" ] || [ -z "${ROOTFS_DIR:-}" ]; then
		return
	fi
	
	local user_home="${ROOTFS_DIR}/home/${FIRST_USER_NAME}"
	local validation_source="${step_dir}/${VALIDATION_STEPS_DIR_NAME}"
	local validation_dest="${user_home}/${VALIDATION_STEPS_DIR_NAME}/${stage_name}/${step_name}/${VALIDATION_STEPS_DIR_NAME}"
	
	# Only proceed if source validation directory exists
	if [ ! -d "${validation_source}" ]; then
		return
	fi
	
	# Create destination directory structure
	mkdir -p "${validation_dest}"
	
	# Install validation files with proper permissions
	local install_opts=""
	if [ -n "${FIRST_USER_ID:-}" ]; then
		install_opts="-o ${FIRST_USER_ID} -g ${FIRST_USER_ID}"
	fi
	
	# Install each file in the validation source directory
	find "${validation_source}" -type f -name "*.sh" -exec install -m 755 ${install_opts} {} "${validation_dest}/" \;
	find "${validation_source}" -type f ! -name "*.sh" -exec install -m 644 ${install_opts} {} "${validation_dest}" \;
	
	log "Validation files installed: ${stage_name}/${step_name} -> ${validation_dest}"
}

# Run build-time validations for a step (excludes runtime validations)
run_build_time_validations() {
	local step_dir="$1"
	local validation_source="${step_dir}/${VALIDATION_STEPS_DIR_NAME}"
	
	# Only proceed if source validation directory exists
	if [ ! -d "${validation_source}" ]; then
		return
	fi
	
	# Check if we have the validation system available
	if [ ! -f "${SCRIPT_DIR}/validate-system.sh" ]; then
		log "Validation system not found - skipping build-time validations"
		return
	fi
	
	local has_validations=false
	local validation_count=0
	local passed_validations=0
	
	# Set up environment for build-time validation
	export ROOTFS_DIR="${ROOTFS_DIR}"
	export STAGE_NAME="${STAGE}"
	export IMG_NAME="${IMG_NAME:-raspios}"
	
	# Run each non-runtime validation script
	for validation_file in "${validation_source}"/*.sh; do
		if [ -f "${validation_file}" ]; then
			local validation_name=$(basename "${validation_file}" .sh)
			
			# Skip runtime validations during build
			if [[ "$validation_name" == *"_runtime" ]]; then
				log "Skipping runtime validation during build: ${validation_name}"
				continue
			fi
			
			has_validations=true
			validation_count=$((validation_count + 1))
			
			log "Running build-time validation: ${validation_name}"
			
			# Make sure the validation script is executable
			chmod +x "${validation_file}"
			
			# Run the validation script in a subshell to isolate environment
			if (
				cd "${validation_source}"
				# Set up minimal environment for validation
				export PATH="${PATH}:${SCRIPT_DIR}"
				source "${SCRIPT_DIR}/validation-framework.sh"
				
				# Run the validation
				bash "${validation_file}"
			); then
				log "✅ Build validation passed: ${validation_name}"
				passed_validations=$((passed_validations + 1))
			else
				log "❌ Build validation failed: ${validation_name}"
				# Note: We don't fail the build on validation errors
				# This allows the build to continue but alerts to issues
			fi
		fi
	done
	
	if [ "$has_validations" = true ]; then
		log "Build-time validation summary: ${passed_validations}/${validation_count} passed"
		if [ $passed_validations -eq $validation_count ]; then
			log "✅ All build-time validations passed for $(basename "$step_dir")"
		else
			log "⚠️  Some build-time validations failed for $(basename "$step_dir") - check above"
			exit 1
		fi
	fi
}


run_stage(){
	log "Begin ${STAGE_DIR}"
	STAGE="$(basename "${STAGE_DIR}")"

	pushd "${STAGE_DIR}" > /dev/null

	STAGE_WORK_DIR="${WORK_DIR}/${STAGE}"
	ROOTFS_DIR="${STAGE_WORK_DIR}"/rootfs

	unmount "${WORK_DIR}/${STAGE}"

	if [ ! -f SKIP_IMAGES ]; then
		if [ -f "${STAGE_DIR}/EXPORT_IMAGE" ]; then
			EXPORT_DIRS="${EXPORT_DIRS} ${STAGE_DIR}"
		fi
	fi
	if [ ! -f SKIP ]; then
		if [ "${CLEAN}" = "1" ]; then
			if [ -d "${ROOTFS_DIR}" ]; then
				rm -rf "${ROOTFS_DIR}"
			fi
		fi
		if [ -x prerun.sh ]; then
			log "Begin ${STAGE_DIR}/prerun.sh"
			./prerun.sh
			log "End ${STAGE_DIR}/prerun.sh"
		fi
		for SUB_STAGE_DIR in "${STAGE_DIR}"/*; do
			if [ -d "${SUB_STAGE_DIR}" ] && [ ! -f "${SUB_STAGE_DIR}/SKIP" ]; then
				run_sub_stage
			fi
		done
	fi

	unmount "${WORK_DIR}/${STAGE}"

	PREV_STAGE="${STAGE}"
	PREV_STAGE_DIR="${STAGE_DIR}"
	PREV_ROOTFS_DIR="${ROOTFS_DIR}"
	popd > /dev/null
	log "End ${STAGE_DIR}"
}

term() {
	if [ "$?" -ne 0 ]; then
		log "Build failed"
	else
		log "Build finished"
	fi
	unmount "${STAGE_WORK_DIR}"
	if [ "$STAGE" = "export-image" ]; then
		for img in "${STAGE_WORK_DIR}/"*.img; do
			unmount_image "$img"
		done
	fi
}

if [ "$(id -u)" != "0" ]; then
	echo "Please run as root" 1>&2
	exit 1
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $BASE_DIR = *" "* ]]; then
	echo "There is a space in the base path of pi-gen"
	echo "This is not a valid setup supported by debootstrap."
	echo "Please remove the spaces, or move pi-gen directory to a base path without spaces" 1>&2
	exit 1
fi

export BASE_DIR

if [ -f config ]; then
	# shellcheck disable=SC1091
	source config
fi

while getopts "c:" flag
do
	case "$flag" in
		c)
			EXTRA_CONFIG="$OPTARG"
			# shellcheck disable=SC1090
			source "$EXTRA_CONFIG"
			;;
		*)
			;;
	esac
done

export PI_GEN=${PI_GEN:-pi-gen}
export PI_GEN_REPO=${PI_GEN_REPO:-https://github.com/RPi-Distro/pi-gen}
export PI_GEN_RELEASE=${PI_GEN_RELEASE:-Raspberry Pi reference}

export ARCH=arm64
export RELEASE=${RELEASE:-bookworm} # Don't forget to update stage0/prerun.sh
export IMG_NAME="${IMG_NAME:-raspios-$RELEASE-$ARCH}"

export USE_QEMU="${USE_QEMU:-0}"
export IMG_DATE="${IMG_DATE:-"$(date +%Y-%m-%d)"}"
export IMG_FILENAME="${IMG_FILENAME:-"${IMG_DATE}-${IMG_NAME}"}"
export ARCHIVE_FILENAME="${ARCHIVE_FILENAME:-"image_${IMG_DATE}-${IMG_NAME}"}"

SCRIPT_DIR="${BASE_DIR}/scripts"
export WORK_DIR="${WORK_DIR:-"${BASE_DIR}/work/${IMG_NAME}"}"
export DEPLOY_DIR=${DEPLOY_DIR:-"${BASE_DIR}/deploy"}

# DEPLOY_ZIP was deprecated in favor of DEPLOY_COMPRESSION
# This preserve the old behavior with DEPLOY_ZIP=0 where no archive was created
if [ -z "${DEPLOY_COMPRESSION}" ] && [ "${DEPLOY_ZIP:-1}" = "0" ]; then
	echo "DEPLOY_ZIP has been deprecated in favor of DEPLOY_COMPRESSION"
	echo "Similar behavior to DEPLOY_ZIP=0 can be obtained with DEPLOY_COMPRESSION=none"
	echo "Please update your config file"
	DEPLOY_COMPRESSION=none
fi
export DEPLOY_COMPRESSION=${DEPLOY_COMPRESSION:-zip}
export COMPRESSION_LEVEL=${COMPRESSION_LEVEL:-6}
export LOG_FILE="${WORK_DIR}/build.log"

export TARGET_HOSTNAME=${TARGET_HOSTNAME:-raspberrypi}

export FIRST_USER_NAME=${FIRST_USER_NAME:-pi}
export FIRST_USER_PASS
export DISABLE_FIRST_BOOT_USER_RENAME=${DISABLE_FIRST_BOOT_USER_RENAME:-0}
export WPA_COUNTRY
export ENABLE_SSH="${ENABLE_SSH:-0}"
export PUBKEY_ONLY_SSH="${PUBKEY_ONLY_SSH:-0}"

export LOCALE_DEFAULT="${LOCALE_DEFAULT:-en_GB.UTF-8}"

export KEYBOARD_KEYMAP="${KEYBOARD_KEYMAP:-gb}"
export KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-English (UK)}"

export TIMEZONE_DEFAULT="${TIMEZONE_DEFAULT:-Europe/London}"

export GIT_HASH=${GIT_HASH:-"$(git rev-parse HEAD)"}

export PUBKEY_SSH_FIRST_USER

export CLEAN
export APT_PROXY
export TEMP_REPO

export STAGE
export STAGE_DIR
export STAGE_WORK_DIR
export PREV_STAGE
export PREV_STAGE_DIR
export ROOTFS_DIR
export PREV_ROOTFS_DIR
export IMG_SUFFIX
export NOOBS_NAME
export NOOBS_DESCRIPTION
export EXPORT_DIR
export EXPORT_ROOTFS_DIR

export QUILT_PATCHES
export QUILT_NO_DIFF_INDEX=1
export QUILT_NO_DIFF_TIMESTAMPS=1
export QUILT_REFRESH_ARGS="-p ab"

# Validation system paths
export VALIDATION_STEPS_DIR_NAME="validations"

# shellcheck source=scripts/common
source "${SCRIPT_DIR}/logging.sh"
# shellcheck source=scripts/common
source "${SCRIPT_DIR}/common"
# shellcheck source=scripts/dependencies_check
source "${SCRIPT_DIR}/dependencies_check"

if [ "$SETFCAP" != "1" ]; then
	export CAPSH_ARG="--drop=cap_setfcap"
fi

mkdir -p "${WORK_DIR}"
trap term EXIT INT TERM

dependencies_check "${BASE_DIR}/depends"


PAGESIZE=$(getconf PAGESIZE)
if [ "$ARCH" == "armhf" ] && [ "$PAGESIZE" != "4096" ]; then
	echo
	echo "ERROR: Building an $ARCH image requires a kernel with a 4k page size (current: $PAGESIZE)"
	echo "On Raspberry Pi OS (64-bit), you can switch to a suitable kernel by adding the following to /boot/firmware/config.txt and rebooting:"
	echo
	echo "kernel=kernel8.img"
	echo "initramfs initramfs8 followkernel"
	echo
	exit 1
fi

echo "Checking native $ARCH executable support..."
if ! arch-test -n "$ARCH"; then
	echo "WARNING: Only a native build environment is supported. Checking emulated support..."
	if ! arch-test "$ARCH"; then
		echo "No fallback mechanism found. Ensure your OS has binfmt_misc support enabled and configured."
		exit 1
	fi
fi

#check username is valid
if [[ ! "$FIRST_USER_NAME" =~ ^[a-z][-a-z0-9_]*$ ]]; then
	echo "Invalid FIRST_USER_NAME: $FIRST_USER_NAME"
	exit 1
fi

if [[ "$DISABLE_FIRST_BOOT_USER_RENAME" == "1" ]] && [ -z "${FIRST_USER_PASS}" ]; then
	echo "To disable user rename on first boot, FIRST_USER_PASS needs to be set"
	echo "Not setting FIRST_USER_PASS makes your system vulnerable and open to cyberattacks"
	exit 1
fi

if [[ "$DISABLE_FIRST_BOOT_USER_RENAME" == "1" ]]; then
	echo "User rename on the first boot is disabled"
	echo "Be advised of the security risks linked to shipping a device with default username/password set."
fi

if [[ -n "${APT_PROXY}" ]] && ! curl --silent "${APT_PROXY}" >/dev/null ; then
	echo "Could not reach APT_PROXY server: ${APT_PROXY}"
	exit 1
fi

if [[ -n "${WPA_PASSWORD}" && ${#WPA_PASSWORD} -lt 8 || ${#WPA_PASSWORD} -gt 63  ]] ; then
	echo "WPA_PASSWORD" must be between 8 and 63 characters
	exit 1
fi

if [[ "${PUBKEY_ONLY_SSH}" = "1" && -z "${PUBKEY_SSH_FIRST_USER}" ]]; then
	echo "Must set 'PUBKEY_SSH_FIRST_USER' to a valid SSH public key if using PUBKEY_ONLY_SSH"
	exit 1
fi

log "Begin ${BASE_DIR}"

STAGE_LIST=${STAGE_LIST:-${BASE_DIR}/stage*}
export STAGE_LIST

EXPORT_CONFIG_DIR=$(realpath "${EXPORT_CONFIG_DIR:-"${BASE_DIR}/export-image"}")
if [ ! -d "${EXPORT_CONFIG_DIR}" ]; then
	echo "EXPORT_CONFIG_DIR invalid: ${EXPORT_CONFIG_DIR} does not exist"
	exit 1
fi
export EXPORT_CONFIG_DIR

for STAGE_DIR in $STAGE_LIST; do
	STAGE_DIR=$(realpath "${STAGE_DIR}")
	run_stage
done

CLEAN=1
for EXPORT_DIR in ${EXPORT_DIRS}; do
	STAGE_DIR=${EXPORT_CONFIG_DIR}
	# shellcheck source=/dev/null
	source "${EXPORT_DIR}/EXPORT_IMAGE"
	EXPORT_ROOTFS_DIR=${WORK_DIR}/$(basename "${EXPORT_DIR}")/rootfs
	run_stage
	if [ "${USE_QEMU}" != "1" ]; then
		if [ -e "${EXPORT_DIR}/EXPORT_NOOBS" ]; then
			# shellcheck source=/dev/null
			source "${EXPORT_DIR}/EXPORT_NOOBS"
			STAGE_DIR="${BASE_DIR}/export-noobs"
			run_stage
		fi
	fi
done

if [ -x "${BASE_DIR}/postrun.sh" ]; then
	log "Begin postrun.sh"
	cd "${BASE_DIR}"
	./postrun.sh
	log "End postrun.sh"
fi

log "End ${BASE_DIR}"
