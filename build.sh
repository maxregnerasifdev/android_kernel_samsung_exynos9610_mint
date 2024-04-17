#!/bin/bash
# =========================================
#         _____              _      
#        |  ___| __ ___  ___| |__   
#        | |_ | '__/ _ \/ __| '_ \  
#        |  _|| | |  __/\__ \ | | | 
#        |_|  |_|  \___||___/_| |_| 
#                              
# =========================================
#  
#  Minty - The kernel build script for Mint
#  The Fresh Project
#  Copyright (C) 2019-2021 TenSeventy7
#  
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#  
#  =========================
#

# Utility directories
ORIGIN_DIR=$(pwd)
CURRENT_BUILD_USER=$(whoami)

# Toolchain options
BUILD_PREF_COMPILER='clang'
BUILD_PREF_COMPILER_VERSION='proton'

# Local toolchain directory
TOOLCHAIN=$HOME/toolchains/exynos9610_toolchains_fresh

# External toolchain directory
TOOLCHAIN_EXT=$(pwd)/toolchain

DEVICE_DB_DIR="${ORIGIN_DIR}/Documentation/device-db"

export ARCH=arm64
export SUBARCH=arm64
export ANDROID_MAJOR_VERSION=r
export PLATFORM_VERSION=11.0.0
export $ARCH

script_echo() {
	echo "  $1"
}

exit_script() {
	kill -INT $$
}

download_toolchain() {
	git clone https://gitlab.com/TenSeventy7/exynos9610_toolchains_fresh.git ${TOOLCHAIN_EXT} --single-branch -b ${BUILD_PREF_COMPILER_VERSION} --depth 1 2>&1 | sed 's/^/     /'
	verify_toolchain
}

verify_toolchain() {
	sleep 2
	script_echo " "

	if [[ -d "${TOOLCHAIN}" ]]; then
		script_echo "I: Toolchain found at default location"
		export PATH="${TOOLCHAIN}/bin:$PATH"
		export LD_LIBRARY_PATH="${TOOLCHAIN}/lib:$LD_LIBRARY_PATH"
	elif [[ -d "${TOOLCHAIN_EXT}" ]]; then

		script_echo "I: Toolchain found at repository root"

		cd ${TOOLCHAIN_EXT}
		git pull
		cd ${ORIGIN_DIR}

		export PATH="${TOOLCHAIN_EXT}/bin:$PATH"
		export LD_LIBRARY_PATH="${TOOLCHAIN_EXT}/lib:$LD_LIBRARY_PATH"

		if [[ ${BUILD_KERNEL_CI} == 'true' ]]; then
			if [[ ${BUILD_PREF_COMPILER_VERSION} == 'proton' ]]; then
				sudo mkdir -p /root/build/install/aarch64-linux-gnu
				sudo cp -r "${TOOLCHAIN_EXT}/lib" /root/build/install/aarch64-linux-gnu/

				sudo chown ${CURRENT_BUILD_USER} /root
				sudo chown ${CURRENT_BUILD_USER} /root/build
				sudo chown ${CURRENT_BUILD_USER} /root/build/install
				sudo chown ${CURRENT_BUILD_USER} /root/build/install/aarch64-linux-gnu
				sudo chown ${CURRENT_BUILD_USER} /root/build/install/aarch64-linux-gnu/lib
			fi
		fi
	else
		script_echo "I: Toolchain not found at default location or repository root"
		script_echo "   Downloading recommended toolchain at ${TOOLCHAIN_EXT}..."
		download_toolchain
	fi

	# Proton Clang 13
	# export CLANG_TRIPLE=aarch64-linux-gnu-
	export CROSS_COMPILE=aarch64-linux-gnu-
	export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
	export CC=${BUILD_PREF_COMPILER}
}

update_magisk() {
	script_echo " "
	script_echo "I: Updating Magisk..."

	if [[ "x${BUILD_KERNEL_MAGISK_BRANCH}" == "xcanary" ]]; then
		MAGISK_BRANCH="canary"
	elif [[ "x${BUILD_KERNEL_MAGISK_BRANCH}" == "xlocal" ]]; then
		MAGISK_BRANCH="local"
	else
		MAGISK_BRANCH=""
	fi

	${ORIGIN_DIR}/usr/magisk/update_magisk.sh ${MAGISK_BRANCH} 2>&1 | sed 's/^/     /'
}

fill_magisk_config() {
	MAGISK_USR_DIR="${ORIGIN_DIR}/usr/magisk/"

	script_echo " "
	script_echo "I: Configuring Magisk..."

	if [[ -f "$MAGISK_USR_DIR/backup_magisk" ]]; then
		rm "$MAGISK_USR_DIR/backup_magisk"
	fi

	echo "KEEPVERITY=true" >> "$MAGISK_USR_DIR/backup_magisk"
	echo "KEEPFORCEENCRYPT=true" >> "$MAGISK_USR_DIR/backup_magisk"
	echo "RECOVERYMODE=false" >> "$MAGISK_USR_DIR/backup_magisk"
	echo "PREINITDEVICE=userdata" >> "$MAGISK_USR_DIR/backup_magisk"

	# Create a unique random seed per-build
	script_echo "   - Generating a unique random seed for this build..."
	RANDOMSEED=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)
	echo "RANDOMSEED=0x$RANDOMSEED" >> "$MAGISK_USR_DIR/backup_magisk"
}

show_usage() {
	script_echo "Usage: ./build.sh -d|--device <device> -v|--variant <variant> [main options]"
	script_echo " "
	script_echo "Main options:"
	script_echo "-d, --device <device>     Set build device to build the kernel for. Required."
	script_echo "-a, --android <version>   Set Android version to build the kernel for. (Default: 11)"
	script_echo "-v, --variant <variant>   Set build variant to build the kernel for. Required."
	script_echo " "
	script_echo "-n, --no-clean            Do not clean and update Magisk before build."
	script_echo "-m, --magisk [canary]     Pre-root the kernel with Magisk. Optional flag to use canary builds."
	script_echo "                          Not available for 'recovery' variant."
	script_echo "-p, --permissive          Build kernel with SELinux fully permissive. NOT RECOMMENDED!"
	script_echo " "
	script_echo "-h, --help                Show this message."
	script_echo " "
	script_echo "Additional options can be found in the script."
}

cleanup() {
	script_echo "I: Cleaning up..."

	if [[ ${BUILD_KERNEL_CLEAN} == 'true' ]]; then
		script_echo "   - Cleaning up build environment..."
		make clean && make mrproper
	fi

	if [[ ${BUILD_MAGISK_UPDATE} == 'true' ]]; then
		update_magisk
	fi

	if [[ ${BUILD_MAGISK_CONFIG} == 'true' ]]; then
		fill_magisk_config
	fi
}

set_file_name() {
	if [[ ${BUILD_KERNEL_BRANCH} != "" ]]; then
		KERNEL_BRANCH="-${BUILD_KERNEL_BRANCH}"
	fi

	KERNEL_VERSION=$(make kernelversion)
	KERNEL_PATCHLEVEL=$(make kernelversion | cut -d'.' -f2)
	KERNEL_SUBLEVEL=$(make kernelversion | cut -d'.' -f3)

	if [[ ${BUILD_KERNEL_VARIANT} == 'canary' ]]; then
		# VersionCode example: 14 -> 14.00
		VERSION_CODE=$(printf "%02d" ${KERNEL_SUBLEVEL})
	else
		VERSION_CODE=${KERNEL_SUBLEVEL}
	fi

	FILE_NAME="${DEVICE}-${KERNEL_VERSION}.${VERSION_CODE}${KERNEL_BRANCH}-$(date +%Y%m%d-%H%M%S)-${BUILD_KERNEL_VARIANT}"
}

build_kernel() {
	script_echo " "
	script_echo "I: Building kernel..."

	if [[ ${BUILD_KERNEL_PERMISSIVE} == 'true' ]]; then
		script_echo "   WARNING: Building with SELinux fully permissive!"
	fi

	if [[ ${BUILD_PREF_COMPILER} == 'clang' ]]; then
		script_echo "   - Using Clang ${BUILD_PREF_COMPILER_VERSION} toolchain..."
	else
		script_echo "   - Using GCC ${BUILD_PREF_COMPILER_VERSION} toolchain..."
	fi

	if [[ ${BUILD_KERNEL_PERMISSIVE} == 'true' ]]; then
		make -j$(nproc --all) O=out ARCH=arm64 ${DEVICE_CONFIG} SELINUX_DEFCONFIG=selinux_defconfig ${BUILD_PREF_COMPILER}_permissive 2>&1 | sed 's/^/     /'
	else
		make -j$(nproc --all) O=out ARCH=arm64 ${DEVICE_CONFIG} SELINUX_DEFCONFIG=selinux_defconfig ${BUILD_PREF_COMPILER} 2>&1 | sed 's/^/     /'
	fi

	if [[ $? -eq 0 ]]; then
		script_echo "   - Kernel built successfully!"
	else
		script_echo "E: Failed to build kernel!"
		exit_script
	fi
}

build_image() {
	script_echo " "
	script_echo "I: Building image..."

	VERSION=$(cat ${ANDROID_DIR}/core/version_defaults.mk | grep "PLATFORM_VERSION := " | sed 's/PLATFORM_VERSION := //g')
	PATCHLEVEL=$(cat ${ANDROID_DIR}/core/version_defaults.mk | grep "PLATFORM_SECURITY_PATCH :=" | sed 's/PLATFORM_SECURITY_PATCH := //g')
	SUBLEVEL=$(cat ${ANDROID_DIR}/core/version_defaults.mk | grep "PLATFORM_VERSION_CODENAME :=" | sed 's/PLATFORM_VERSION_CODENAME := //g')

	script_echo "   - Android version: ${VERSION} (Security patch level: ${PATCHLEVEL})"
}

build_package() {
	script_echo " "
	script_echo "I: Packaging kernel..."

	mkdir -p "${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}"

	cp ${ORIGIN_DIR}/out/arch/arm64/boot/Image.gz-dtb ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.img
	cp ${ORIGIN_DIR}/out/arch/arm64/boot/dtbo.img ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-dtbo.img

	if [[ ${BUILD_KERNEL_VARIANT} == 'recovery' ]]; then
		cp ${ORIGIN_DIR}/out/arch/arm64/boot/recovery.img ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-recovery.img
	fi

	echo "DEVICE=${DEVICE}" > ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "VARIANT=${BUILD_KERNEL_VARIANT}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "VERSION=${VERSION}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "PATCHLEVEL=${PATCHLEVEL}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "SUBLEVEL=${SUBLEVEL}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "KERNEL_VERSION=${KERNEL_VERSION}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "KERNEL_PATCHLEVEL=${KERNEL_PATCHLEVEL}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "KERNEL_SUBLEVEL=${KERNEL_SUBLEVEL}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop
	echo "TIMESTAMP=$(date +%Y%m%d-%H%M%S)" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop

	cp ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}.prop ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-flashable.prop

	echo "VERSION=${VERSION}" > ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/mint.prop
	echo "PATCHLEVEL=${PATCHLEVEL}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/mint.prop
	echo "SUBLEVEL=${SUBLEVEL}" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/mint.prop
	echo "TIMESTAMP=$(date +%Y%m%d-%H%M%S)" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/mint.prop

	echo "#!/system/bin/sh" > ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-flashable.sh
	echo "dd if=/data/media/0/Download/${FILE_NAME}.img of=/dev/block/by-name/boot bs=1M && sync" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-flashable.sh
	echo "dd if=/data/media/0/Download/${FILE_NAME}-dtbo.img of=/dev/block/by-name/dtbo bs=1M && sync" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-flashable.sh

	if [[ ${BUILD_KERNEL_VARIANT} == 'recovery' ]]; then
		echo "dd if=/data/media/0/Download/${FILE_NAME}-recovery.img of=/dev/block/by-name/recovery bs=1M && sync" >> ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-flashable.sh
	fi

	chmod +x ${ORIGIN_DIR}/out/${DEVICE}/${BUILD_KERNEL_VARIANT}/${FILE_NAME}-flashable.sh
}

# Default values
BUILD_KERNEL_CLEAN='true'
BUILD_MAGISK_UPDATE='false'
BUILD_MAGISK_CONFIG='false'
BUILD_KERNEL_PERMISSIVE='false'
BUILD_KERNEL_CI='false'

# Process command-line arguments
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-d|--device)
		DEVICE="$2"
		shift # past argument
		shift # past value
		;;
		-a|--android)
		PLATFORM_VERSION="$2"
		shift # past argument
		shift # past value
		;;
		-v|--variant)
		BUILD_KERNEL_VARIANT="$2"
		shift # past argument
		shift # past value
		;;
		-n|--no-clean)
		BUILD_KERNEL_CLEAN='false'
		shift # past argument
		;;
		-m|--magisk)
		BUILD_KERNEL_MAGISK_BRANCH="$2"
		BUILD_MAGISK_UPDATE='true'
		BUILD_MAGISK_CONFIG='true'
		shift # past argument
		shift # past value
		;;
		-p|--permissive)
		BUILD_KERNEL_PERMISSIVE='true'
		shift # past argument
		;;
		--ci)
		BUILD_KERNEL_CI='true'
		shift # past argument
		;;
		-h|--help)
		show_usage
		exit
		;;
		*)
		script_echo "E: Unknown option: $1"
		show_usage
		exit 1
		;;
	esac
done

# Check if required options are set
if [[ -z "${DEVICE}" || -z "${BUILD_KERNEL_VARIANT}" ]]; then
	script_echo "E: Missing required options!"
	show_usage
	exit 1
fi

# Initialize Android directories
ANDROID_DIR="${ORIGIN_DIR}/android-${PLATFORM_VERSION}"
DEVICE_DIR="${ANDROID_DIR}/device/${DEVICE}"

# Load the configuration for the specified device
DEVICE_CONFIG="${DEVICE}_${BUILD_KERNEL_VARIANT}_defconfig"
if [[ ! -f "${DEVICE_DB_DIR}/${DEVICE_CONFIG}" ]]; then
	script_echo "E: Device configuration '${DEVICE_CONFIG}' not found!"
	exit 1
fi

# Main script logic
cleanup
download_toolchain
build_kernel
build_image
build_package
