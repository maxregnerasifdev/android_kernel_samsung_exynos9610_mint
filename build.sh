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
    script_echo "-k, --kernelsu            Pre-root the kernel with KernelSU."
    script_echo "                          Not available for 'recovery' variant."
    script_echo "-p, --permissive          Build kernel with SELinux fully permissive. NOT RECOMMENDED!"
    script_echo " "
    script_echo "-h, --help                Show this message."
    script_echo " "
    script_echo "Variant options:"
    script_echo "    oneui: Build Mint for use with stock and One UI-based ROMs."
    script_echo "     aosp: Build Mint for use with AOSP and AOSP-based Generic System Images (GSIs)."
    script_echo " recovery: Build Mint for use with recovery device trees. Doesn't build a ZIP."
    script_echo " "
    script_echo "Supported devices:"
    script_echo "  a50 (Samsung Galaxy A50)"
    script_echo " a50s (Samsung Galaxy A50s)"
    exit_script
}

merge_config() {
    if [[ ! -e "${SUB_CONFIGS_DIR}/mint_${1}.config" ]]; then
        script_echo "E: Subconfig not found on config DB!"
        script_echo "   ${SUB_CONFIGS_DIR}/mint_${1}.config"
        script_echo "   Make sure it is in the proper directory."
        script_echo " "
        exit_script
    else
        echo "$(cat "${SUB_CONFIGS_DIR}/mint_${1}.config")" >> "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
    fi
}

set_android_version() {
    echo "CONFIG_MINT_PLATFORM_VERSION=${BUILD_ANDROID_PLATFORM}" >> "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
}

get_devicedb_info() {
    case ${BUILD_DEVICE} in
        "a50")
            DEVICE_BOARD_CONFIG="universal9610_defconfig"
            ;;
        "a50s")
            DEVICE_BOARD_CONFIG="a50s_defconfig"
            ;;
    esac
}

source_helpers() {
    for file in "${ORIGIN_DIR}"/utils/helpers/*.sh; do
        if [[ -f $file ]]; then
            source $file
        fi
    done
}

get_subconfigs() {
    for config in "${SUB_CONFIGS_DIR}"/*.config; do
        if [[ -f "${config}" ]]; then
            CONFIG_NAME=$(basename ${config})
            SUB_CONFIGS_LIST+=("${CONFIG_NAME%.*}")
        fi
    done
}

source_helpers

# Main

BUILD_DEVICE=""
BUILD_VARIANT=""
BUILD_KERNEL_CLEAN=true
BUILD_KERNEL_SU=false
BUILD_KERNEL_MAGISK=false
BUILD_KERNEL_CANARY=false
BUILD_KERNEL_PERMISSIVE=false
BUILD_KERNEL_CI=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--device)
            BUILD_DEVICE="$2"
            shift
            shift
            ;;
        -v|--variant)
            BUILD_VARIANT="$2"
            shift
            shift
            ;;
        -n|--no-clean)
            BUILD_KERNEL_CLEAN=false
            shift
            ;;
        -m|--magisk)
            BUILD_KERNEL_MAGISK=true
            if [[ "$2" == "canary" ]]; then
                BUILD_KERNEL_CANARY=true
                shift
            fi
            shift
            ;;
        -k|--kernelsu)
            BUILD_KERNEL_SU=true
            shift
            ;;
        -p|--permissive)
            BUILD_KERNEL_PERMISSIVE=true
            shift
            ;;
        -a|--android)
            BUILD_ANDROID_PLATFORM="$2"
            shift
            shift
            ;;
        --ci)
            BUILD_KERNEL_CI=true
            shift
            ;;
        *)
            show_usage
            ;;
    esac
done

if [[ "x${BUILD_DEVICE}" == "x" || "x${BUILD_VARIANT}" == "x" ]]; then
    show_usage
fi

case ${BUILD_VARIANT} in
    oneui)
        DEVICE_REPO_DIR="${ORIGIN_DIR}/devices/samsung/universal9610"
        SUB_CONFIGS_DIR="${DEVICE_REPO_DIR}/configs"
        ;;
    aosp)
        DEVICE_REPO_DIR="${ORIGIN_DIR}/devices/generic/common"
        SUB_CONFIGS_DIR="${DEVICE_REPO_DIR}/configs"
        ;;
    recovery)
        DEVICE_REPO_DIR="${ORIGIN_DIR}/devices/recovery"
        SUB_CONFIGS_DIR="${DEVICE_REPO_DIR}/configs"
        ;;
    *)
        script_echo "E: Unknown variant!"
        script_echo "   ${BUILD_VARIANT}"
        show_usage
        ;;
esac

get_devicedb_info

if [[ "${BUILD_KERNEL_MAGISK}" == true ]]; then
    update_magisk
fi

if [[ "${BUILD_KERNEL_PERMISSIVE}" == true ]]; then
    script_echo " "
    script_echo "I: Setting SELinux to fully permissive..."
    echo "CONFIG_SECURITY_SELINUX_BOOTPARAM_VALUE=0" >> "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
    echo "CONFIG_SECURITY_SELINUX_DISABLE=y" >> "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
    echo "CONFIG_SECURITY_SELINUX_DEVELOP=y" >> "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
fi

if [[ ! -f "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}" ]]; then
    merge_config "${BUILD_DEVICE_TMP_CONFIG}"
    set_android_version
fi

if [[ ! -d "${DEVICE_REPO_DIR}" ]]; then
    script_echo "E: Device tree not found on repository!"
    script_echo "   ${DEVICE_REPO_DIR}"
    exit_script
fi

if [[ ! -d "${SUB_CONFIGS_DIR}" ]]; then
    script_echo "E: Subconfigs not found on repository!"
    script_echo "   ${SUB_CONFIGS_DIR}"
    exit_script
fi

get_subconfigs

if [[ ! "${SUB_CONFIGS_LIST[@]}" ]]; then
    script_echo "E: Subconfigs not found on repository!"
    script_echo "   ${SUB_CONFIGS_DIR}"
    exit_script
fi

cd "${ORIGIN_DIR}" || exit

if [[ "${BUILD_KERNEL_CI}" == true ]]; then
    verify_toolchain
fi

make ${DEVICE_BOARD_CONFIG}
