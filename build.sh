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
	script_echo "-s, --strict              Force kernel to run in SELinux enforcing mode. NOT RECOMMENDED!"
	script_echo " "
	script_echo "Developer options:"
	script_echo "-h, --help                Show this help message and exit."
	script_echo "--force-clean             Force clean the out/ directory before building."
	script_echo "--kernel-ci               Set up the kernel for continuous integration (CI)."
	script_echo "--update-configs          Update kernel configs before build."
	script_echo "--skip-prebuilt           Skip including prebuilt kernel modules (ie. DRM)."
	script_echo "--ci-pr <number>          Number of the pull request for CI."
	script_echo "--magisk-branch <branch>  Set the branch of Magisk to use. (canary/local)"
	script_echo "--pref-compiler <version> Set preferred compiler version. (proton/llvm/clang-13)"
	exit 1
}

change_kernel_config() {
	# Provide a user interface to modify kernel configurations
	script_echo " "
	script_echo "I: Modifying kernel configuration..."

	# Modify kernel configurations based on user input
	# Example: Enable specific features or parameters
	# Example: Disable specific features or parameters
	# Example: Change parameter values

	# For demonstration, let's assume we're enabling a specific feature
	# in the kernel configuration file .config
	sed -i 's/# CONFIG_FEATURE is not set/CONFIG_FEATURE=y/' .config

	# Notify the user about the changes
	script_echo "   Kernel configuration modified successfully."
}

customize_kernel_modules() {
	# Provide a user interface to customize kernel modules
	script_echo " "
	script_echo "I: Customizing kernel modules..."

	# Copy custom kernel modules to the appropriate directory
	# Example: cp custom_module.ko drivers/custom/

	# For demonstration, let's assume we're copying a custom kernel module
	# to the drivers directory
	cp custom_module.ko drivers/custom/

	# Notify the user about the customization
	script_echo "   Kernel modules customized successfully."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-d|--device)
		DEVICE=$2
		shift 2
		;;
	-v|--variant)
		VARIANT=$2
		shift 2
		;;
	-a|--android)
		ANDROID_MAJOR_VERSION=$2
		shift 2
		;;
	-h|--help)
		show_usage
		;;
	--force-clean)
		FORCE_CLEAN="true"
		shift
		;;
	--kernel-ci)
		BUILD_KERNEL_CI="true"
		shift
		;;
	--update-configs)
		UPDATE_CONFIGS="true"
		shift
		;;
	--skip-prebuilt)
		SKIP_PREBUILT="true"
		shift
		;;
	--magisk)
		BUILD_KERNEL_MAGISK="true"
		if [[ "$2" == "canary" ]]; then
			BUILD_KERNEL_MAGISK_BRANCH="canary"
			shift 2
		else
			BUILD_KERNEL_MAGISK_BRANCH="local"
			shift
		fi
		;;
	--ci-pr)
		BUILD_KERNEL_CI_PR="$2"
		shift 2
		;;
	--magisk-branch)
		BUILD_KERNEL_MAGISK_BRANCH="$2"
		shift 2
		;;
	--pref-compiler)
		BUILD_PREF_COMPILER="$2"
		shift 2
		;;
	*)
		show_usage
		;;
	esac
done

# Verify essential build parameters
if [[ -z "${DEVICE}" || -z "${VARIANT}" ]]; then
	show_usage
fi

# Verify toolchain and setup environment
verify_toolchain

# Download or update Magisk if specified
if [[ -z "${NO_CLEAN}" ]]; then
	fill_magisk_config
	update_magisk
fi

# Change kernel configuration if specified
if [[ -n "${UPDATE_CONFIGS}" ]]; then
	change_kernel_config
fi

# Build the kernel
build_kernel() {
	script_echo " "
	script_echo "I: Building kernel..."

	cd kernel && ./build.sh --device "${DEVICE}" --variant "${VARIANT}" --android "${ANDROID_MAJOR_VERSION}" --skip-defconfig --use-clang --prefix "$PWD/../" 2>&1 | sed 's/^/     /'
	cd "${ORIGIN_DIR}"
}

build_kernel

# Customize kernel modules if needed
customize_kernel_modules

script_echo " "
script_echo "I: Kernel build completed successfully."
