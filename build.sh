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
	script_echo "Variant options:"
	script_echo "    recovery               Build a recovery flashable image."
	script_echo "    boot                   Build a boot image."
	script_echo " "
	script_echo "Example usage:"
	script_echo "   ./build.sh -d hlte -v boot -m"
	script_echo "   ./build.sh -d hlte -v recovery -n"
}

parse_args() {
	script_echo " "
	script_echo "I: Parsing arguments..."

	while [[ $# -gt 0 ]]; do
		case "$1" in
			-d|--device)
				DEVICE="$2"
				shift 2
				;;
			-a|--android)
				ANDROID_MAJOR_VERSION="$2"
				shift 2
				;;
			-v|--variant)
				VARIANT="$2"
				shift 2
				;;
			-n|--no-clean)
				NO_CLEAN=true
				shift
				;;
			-m|--magisk)
				BUILD_MAGISK=true
				BUILD_KERNEL_MAGISK_BRANCH="$2"
				shift 2
				;;
			-p|--permissive)
				PERMISSIVE=true
				shift
				;;
			-h|--help)
				show_usage
				exit_script
				;;
			*)
				script_echo "E: Invalid argument: $1"
				show_usage
				exit_script
				;;
		esac
	done

	if [[ -z "${DEVICE}" || -z "${VARIANT}" ]]; then
		script_echo "E: Device and variant must be specified!"
		show_usage
		exit_script
	fi

	if [[ "${VARIANT}" != "boot" && "${VARIANT}" != "recovery" ]]; then
		script_echo "E: Invalid variant specified!"
		show_usage
		exit_script
	fi

	if [[ "${BUILD_MAGISK}" == "true" && "${VARIANT}" == "recovery" ]]; then
		script_echo "E: Magisk pre-rooting not available for recovery variant!"
		show_usage
		exit_script
	fi
}

prepare_build() {
	script_echo " "
	script_echo "I: Preparing build environment..."

	if [[ "${NO_CLEAN}" != "true" ]]; then
		script_echo "   - Cleaning build environment..."
		make O=out clean 2>&1 | sed 's/^/     /'
	fi

	if [[ "${PERMISSIVE}" == "true" ]]; then
		script_echo "   - Building with SELinux permissive..."
		sed -i '/CONFIG_SECURITY_SELINUX/d' arch/arm64/configs/vendor/${DEVICE}_defconfig
		echo "CONFIG_SECURITY_SELINUX=y" >> arch/arm64/configs/vendor/${DEVICE}_defconfig
		echo "CONFIG_SECURITY_SELINUX_BOOTPARAM=y" >> arch/arm64/configs/vendor/${DEVICE}_defconfig
		echo "CONFIG_SECURITY_SELINUX_DISABLE=y" >> arch/arm64/configs/vendor/${DEVICE}_defconfig
		echo "CONFIG_SECURITY_SELINUX_DEVELOP=y" >> arch/arm64/configs/vendor/${DEVICE}_defconfig
		echo "CONFIG_SECURITY_SELINUX_POLICYDB_VERSION_MAX=" >> arch/arm64/configs/vendor/${DEVICE}_defconfig
	fi

	if [[ "${BUILD_MAGISK}" == "true" ]]; then
		fill_magisk_config
	fi
}

build_kernel() {
	script_echo " "
	script_echo "I: Building kernel image..."

	make O=out ${DEVICE}_defconfig 2>&1 | sed 's/^/     /'
	make O=out -j$(nproc --all) 2>&1 | sed 's/^/     /'

	if [[ $? -eq 0 ]]; then
		script_echo "   - Kernel image successfully built!"
	else
		script_echo "E: Failed to build kernel image!"
		exit_script
	fi
}

build_boot_img() {
	script_echo " "
	script_echo "I: Building boot image..."

	cp out/arch/arm64/boot/Image.gz-dtb out/arch/arm64/boot/Image.gz-dtb.tmp
	"${ANDROID_BUILD_TOP}/mkbootimg/mkboot" --kernel out/arch/arm64/boot/Image.gz-dtb.tmp \
		--ramdisk "${ANDROID_BUILD_TOP}/vendor/${VENDOR}/${DEVICE}/ramdisk.img" \
		--cmdline "androidboot.hardware=${DEVICE} androidboot.selinux=enforcing" \
		--base 0x10000000 \
		--pagesize 4096 \
		--output "${ORIGIN_DIR}/out/boot_${DEVICE}.img" 2>&1 | sed 's/^/     /'
	rm out/arch/arm64/boot/Image.gz-dtb.tmp

	if [[ $? -eq 0 ]]; then
		script_echo "   - Boot image successfully built!"
	else
		script_echo "E: Failed to build boot image!"
		exit_script
	fi
}

build_recovery_img() {
	script_echo " "
	script_echo "I: Building recovery image..."

	cp out/arch/arm64/boot/Image.gz-dtb out/arch/arm64/boot/Image.gz-dtb.tmp
	"${ANDROID_BUILD_TOP}/mkbootimg/mkboot" --kernel out/arch/arm64/boot/Image.gz-dtb.tmp \
		--ramdisk "${ANDROID_BUILD_TOP}/vendor/${VENDOR}/${DEVICE}/ramdisk-recovery.img" \
		--cmdline "androidboot.hardware=${DEVICE} androidboot.selinux=enforcing" \
		--base 0x10000000 \
		--pagesize 4096 \
		--output "${ORIGIN_DIR}/out/recovery_${DEVICE}.img" 2>&1 | sed 's/^/     /'
	rm out/arch/arm64/boot/Image.gz-dtb.tmp

	if [[ $? -eq 0 ]]; then
		script_echo "   - Recovery image successfully built!"
	else
		script_echo "E: Failed to build recovery image!"
		exit_script
	fi
}

main() {
	script_echo " "
	script_echo "Minty - The kernel build script for Mint"
	script_echo "The Fresh Project"
	script_echo "Version 0.1"
	script_echo " "

	parse_args "$@"

	if [[ -n ${ANDROID_BUILD_TOP} ]]; then
		script_echo "I: Android build environment detected"
	else
		script_echo "E: Android build environment not detected"
		exit_script
	fi

	if [[ ! -d ${DEVICE_DB_DIR} ]]; then
		script_echo "E: Device DB not found!"
		exit_script
	fi

	verify_toolchain

	script_echo " "
	script_echo "I: Setting up kernel build for ${DEVICE} (${VARIANT})..."

	source "${DEVICE_DB_DIR}/${DEVICE}.sh"

	prepare_build

	build_kernel

	if [[ "${VARIANT}" == "boot" ]]; then
		build_boot_img
	elif [[ "${VARIANT}" == "recovery" ]]; then
		build_recovery_img
	fi

	if [[ "${BUILD_MAGISK}" == "true" ]]; then
		update_magisk
	fi

	script_echo " "
	script_echo "I: Build completed successfully!"
}

main "$@"
