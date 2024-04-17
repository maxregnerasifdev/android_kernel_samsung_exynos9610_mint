#!/bin/bash
set -eo pipefail

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
    script_echo "    oneui: Build Mint for use with stock and One UI-based ROMs."
    script_echo "     aosp: Build Mint for use with AOSP and AOSP-based Generic System Images (GSIs)."
    script_echo " recovery: Build Mint for use with recovery device trees. Doesn't build a ZIP."
    script_echo " "
    script_echo "Examples:"
    script_echo " "
    script_echo "    Build Mint for the Samsung Galaxy A50 (SM-A505U) for stock-based ROMs:"
    script_echo "    ./build.sh --device a50 --variant oneui"
    script_echo " "
    script_echo "    Build Mint for the Google Pixel 2 (walleye) for AOSP-based GSIs:"
    script_echo "    ./build.sh --device walleye --variant aosp"
    script_echo " "
    script_echo "    Build Mint for the Xiaomi Redmi Note 5 Pro (whyred) for use in a custom recovery:"
    script_echo "    ./build.sh --device whyred --variant recovery"
}

# Parse main arguments
for arg in "$@"
do
    case $arg in
        -d|--device)
            DEVICE=$2
            shift
            shift
            ;;
        -a|--android)
            ANDROID_MAJOR_VERSION=$2
            shift
            shift
            ;;
        -v|--variant)
            VARIANT=$2
            shift
            shift
            ;;
        -n|--no-clean)
            NO_CLEAN=true
            shift
            ;;
        -m|--magisk)
            BUILD_KERNEL_MAGISK=true
            if [[ -n "$2" && "$2" != "canary" ]]; then
                BUILD_KERNEL_MAGISK_BRANCH=$2
                shift
            else
                BUILD_KERNEL_MAGISK_BRANCH="canary"
            fi
            shift
            ;;
        -p|--permissive)
            PERMISSIVE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
done

# Device-specific arguments
case $DEVICE in
    "exynos9610")
        KERNEL_CONFIG=${ORIGIN_DIR}/arch/arm64/configs/fresh-exynos9610_defconfig
        ;;
    *)
        script_echo " "
        script_echo "E: Device not recognized. Please select a valid device."
        show_usage
        exit 1
        ;;
esac

# Variant-specific arguments
case $VARIANT in
    "oneui")
        BUILD_VARIANT=ONEUI
        ;;
    "aosp")
        BUILD_VARIANT=AOSP
        ;;
    "recovery")
        BUILD_VARIANT=RECOVERY
        ;;
    *)
        script_echo " "
        script_echo "E: Variant not recognized. Please select a valid variant."
        show_usage
        exit 1
        ;;
esac

# Clean up and pre-build tasks
if [[ $NO_CLEAN != true ]]; then
    update_magisk
fi

if [[ $BUILD_KERNEL_MAGISK == true ]]; then
    fill_magisk_config
fi

if [[ $PERMISSIVE == true ]]; then
    sed -i 's/CONFIG_SECURITY_SELINUX_DEVELOP=y/CONFIG_SECURITY_SELINUX_DEVELOP=n/g' $KERNEL_CONFIG
fi

# Download toolchain
verify_toolchain

# Start build
script_echo " "
script_echo "I: Starting Mint kernel build for ${DEVICE} ${BUILD_VARIANT}..."

if [[ $VARIANT == "recovery" ]]; then
    make -j$(nproc --all) O=out ARCH=$ARCH ${KERNEL_CONFIG}
else
    make -j$(nproc --all) O=out ARCH=$ARCH ${KERNEL_CONFIG}
    make -j$(nproc --all) O=out ARCH=$ARCH
fi

# Done
script_echo " "
script_echo "I: Mint kernel build completed successfully."
