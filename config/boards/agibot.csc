# Rockchip RK3588, 16 GiB, eMMC, dual GbE, PCIe, HDMI/DP robot carrier
BOARD_NAME="AGIBOT MB0002 V2"
BOARD_VENDOR="agibot"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="community"
INTRODUCED="2026"

# Armbian's RK3588 vendor family uses Radxa next-dev-v2024.10 U-Boot.
# Start from its maintained RK3588 configuration, then make the board-critical
# selections in the post-config hook below. The board-scoped U-Boot patch adds
# only the small control DT used before Linux takes over.
BOOTCONFIG="rock-5b-rk3588_defconfig"
BOOT_SCENARIO="spl-blobs"
BOOTDELAY=3
BOOT_SUPPORT_SPI="no"

KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
BOOT_FDT_FILE="rockchip/rk3588-agibot-mb0002-v2.dtb"

# Use Rockchip's BSP kbase node and Armbian's maintained proprietary G610
# userspace integration. Do not enable the mutually exclusive Panthor overlay.

FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"

# The renamed rk3588 Bluetooth service is not detected by the family-level
# package heuristic, so keep its userspace dependencies explicit.
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

function post_family_config__agibot_mb0002_v2_board_overrides() {
	# rockchip64_common defaults to a zero-second delay after this board file is
	# sourced. Restore a usable recovery window before artifact hashing and the
	# generic U-Boot configuration phase.
	declare -g BOOTDELAY=3
}

function pre_install_distribution_specific__agibot_install_armbian_libmali() {
	# The CLI server/minimal profiles intentionally omit the graphics stack and
	# therefore do not provide libdrm2 at this early image stage.
	[[ "${BUILD_DESKTOP}" == "yes" ]] || return 0

	local package="libmali-valhall-g610-g24p0-x11-wayland-gbm_1.9-1_arm64.deb"
	local release_tag="v1.9-1-20260304-9b413d2"
	local expected_sha256="edc1d2e45b7e16f39e5608075b89e90bd62974257f15ac942f214bef522eb22c"
	local cache_dir="${SRC}/cache/libmali-rockchip"
	local cache_deb="${cache_dir}/${package}"
	local download_url="${GITHUB_SOURCE:-https://github.com}/armbian/libmali-rockchip/releases/download/${release_tag}/${package}"
	local actual_sha256=""

	display_alert "${BOARD}" "Installing Armbian G610 g24p0 libmali" "info"
	run_host_command_logged mkdir -p "${cache_dir}"

	if [[ -f "${cache_deb}" ]]; then
		actual_sha256="$(sha256sum "${cache_deb}" | cut -d ' ' -f 1)"
		if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
			run_host_command_logged rm -f "${cache_deb}"
		fi
	fi

	if [[ ! -f "${cache_deb}" ]]; then
		run_host_command_logged curl -fL --retry 3 \
			-o "${cache_deb}.partial" "${download_url}" \
			|| exit_with_error "Unable to download the pinned Armbian libmali package"
		actual_sha256="$(sha256sum "${cache_deb}.partial" | cut -d ' ' -f 1)"
		if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
			run_host_command_logged rm -f "${cache_deb}.partial"
			exit_with_error "Armbian libmali package checksum mismatch"
		fi
		run_host_command_logged mv "${cache_deb}.partial" "${cache_deb}"
	fi

	install -m 644 "${cache_deb}" "${SDCARD}/tmp/${package}"
	chroot_sdcard_apt_get_install "/tmp/${package}"
	chroot_sdcard ldconfig
	run_host_command_logged rm -f "${SDCARD}/tmp/${package}"
}

function post_config_uboot_target__agibot_mb0002_v2_board_config() {
	[[ "${BRANCH}" == "vendor" ]] || return 0

	display_alert "u-boot for ${BOARD}/${BRANCH}" "Selecting AGIBOT UART2 and eMMC control DT" "info"

	# Radxa's next-dev-v2024.10 branch is based on U-Boot 2017.09 and has no
	# scripts/config. Transform the known official Rock 5B baseline before
	# Armbian's final olddefconfig pass instead of depending on a newer helper.
	# The factory/live DT and serial capture agree on UART2 M0 at 1.5 Mbaud.
	sed -i \
		-e 's|^CONFIG_DEFAULT_DEVICE_TREE=.*|CONFIG_DEFAULT_DEVICE_TREE="rk3588-agibot-mb0002-v2"|' \
		-e 's|^CONFIG_OF_LIST=.*|CONFIG_OF_LIST="rk3588-agibot-mb0002-v2"|' \
		-e 's|^CONFIG_ROCKCHIP_BOOTDEV=.*|CONFIG_ROCKCHIP_BOOTDEV="mmc 0"|' \
		-e 's|^CONFIG_BOOTDELAY=.*|CONFIG_BOOTDELAY=3|' \
		-e 's|^CONFIG_ZERO_BOOTDELAY_CHECK=y|# CONFIG_ZERO_BOOTDELAY_CHECK is not set|' \
		-e 's|^CONFIG_BAUDRATE=.*|CONFIG_BAUDRATE=1500000|' \
		-e 's|^CONFIG_DEBUG_UART_BASE=.*|CONFIG_DEBUG_UART_BASE=0xFEB50000|' \
		-e 's|^CONFIG_DEBUG_UART_CLOCK=.*|CONFIG_DEBUG_UART_CLOCK=24000000|' \
		-e 's|^CONFIG_DEBUG_UART_SHIFT=.*|CONFIG_DEBUG_UART_SHIFT=2|' \
		-e 's|^CONFIG_EFI_PARTITION_ENTRIES_NUMBERS=.*|CONFIG_EFI_PARTITION_ENTRIES_NUMBERS=128|' \
		-e 's|^# CONFIG_GPIO_HOG is not set$|CONFIG_GPIO_HOG=y|' \
		-e 's|^CONFIG_DISABLE_CONSOLE=y|# CONFIG_DISABLE_CONSOLE is not set|' \
		-e 's|^CONFIG_SYS_CONSOLE_INFO_QUIET=y|# CONFIG_SYS_CONSOLE_INFO_QUIET is not set|' \
		-e '/^# CONFIG_DEBUG_UART_ANNOUNCE is not set$/d' \
		.config

	if ! grep -q '^CONFIG_DEBUG_UART_ANNOUNCE=y$' .config; then
		sed -i '/^CONFIG_DEBUG_UART=y$/a CONFIG_DEBUG_UART_ANNOUNCE=y' .config
	fi
}

function post_family_tweaks_bsp__agibot_bluetooth_userspace() {
	display_alert "${BOARD}" "Installing AP6275P Bluetooth userspace loader" "info"

	install -m 755 "${SRC}/packages/bsp/rk3399/brcm_patchram_plus_rk3399" "${destination}/usr/bin/"
	install -d "${destination}/lib/systemd/system"
	cp "${SRC}/packages/bsp/rk3399/rk3399-bluetooth.service" \
		"${destination}/lib/systemd/system/rk3588-bluetooth.service"

	# MB0002 V2 wires AP6275P Bluetooth to UART6 and uses BCM4362A2 patchram.
	sed -i \
		-e 's|/dev/ttyS0|/dev/ttyS6|g' \
		-e 's|/lib/firmware/brcm/BCM4345C5.hcd|/lib/firmware/ap6275p/BCM4362A2.hcd|g' \
		-e 's|brcm_patchram_plus_rk3399 -d |brcm_patchram_plus_rk3399 |g' \
		-e '/^ExecStartPre=\/usr\/sbin\/rfkill unblock all$/i ExecStartPre=/usr/sbin/rfkill block bluetooth' \
		-e '/^ExecStartPre=\/usr\/sbin\/rfkill unblock all$/i ExecStartPre=/usr/bin/sleep 1' \
		-e '/^SysVStartPriority=/d' \
		"${destination}/lib/systemd/system/rk3588-bluetooth.service"
}

function post_family_tweaks_bsp__agibot_usb_port_power() {
	local usb_power_script="${SRC}/packages/bsp/agibot/agibot-usb-port-power"
	local usb_power_service="${SRC}/packages/bsp/agibot/agibot-usb-port-power.service"

	display_alert "${BOARD}" "Installing PCA9555 USB-A port power service" "info"
	[[ -f "${usb_power_script}" ]] \
		|| exit_with_error "Missing AGIBOT USB-A port power script"
	[[ -f "${usb_power_service}" ]] \
		|| exit_with_error "Missing AGIBOT USB-A port power service"

	install -d "${destination}/usr/local/sbin" "${destination}/usr/lib/systemd/system"
	install -m 755 "${usb_power_script}" \
		"${destination}/usr/local/sbin/agibot-usb-port-power"
	install -m 644 "${usb_power_service}" \
		"${destination}/usr/lib/systemd/system/agibot-usb-port-power.service"
}

function post_family_tweaks_bsp__agibot_official_media_permissions() {
	# The RK3588 family intentionally has an empty generic BSP hook. Install
	# Armbian's own Rockchip media rules so desktop users can reach the in-tree
	# MPP, RGA and DMA-heap interfaces without duplicating their drivers.
	install -d "${destination}/etc/udev/rules.d"
	install -m 644 "${SRC}/packages/bsp/rockchip/50-mali.rules" \
		"${destination}/etc/udev/rules.d/50-mali.rules"
	install -m 644 "${SRC}/packages/bsp/rockchip/60-media.rules" \
		"${destination}/etc/udev/rules.d/60-media.rules"
}

function post_family_tweaks__agibot_mali_dma_heap_permissions() {
	display_alert "${BOARD}" "Configuring Mali and DMA-heap permissions" "info"
	install -d "${SDCARD}/etc/udev/rules.d"
	printf '%s\n' 'SUBSYSTEM=="dma_heap", GROUP="render", MODE="0660"' \
		> "${SDCARD}/etc/udev/rules.d/90-agibot-mali-dma-heap.rules"

	local display_user
	for display_user in gdm Debian-gdm; do
		if chroot_sdcard getent passwd "${display_user}" > /dev/null 2>&1; then
			chroot_sdcard usermod -aG render,video "${display_user}"
		fi
	done
}

function post_family_tweaks__agibot_mali_x11_kms_config() {
	[[ "${BUILD_DESKTOP}" == "yes" ]] || return 0

	display_alert "${BOARD}" "Configuring X11 for Rockchip KMS" "info"
	install -d "${SDCARD}/etc/X11/xorg.conf.d"
	printf '%s\n' \
		'Section "OutputClass"' \
		'    Identifier  "RockchipDRM"' \
		'    MatchDriver "rockchip"' \
		'    Driver      "modesetting"' \
		'    Option      "PrimaryGPU" "yes"' \
		'EndSection' \
		> "${SDCARD}/etc/X11/xorg.conf.d/10-rockchip-kms.conf"
}

function post_family_tweaks__agibot_mali_egl_override() {
	[[ "${BUILD_DESKTOP}" == "yes" ]] || return 0

	display_alert "${BOARD}" "Selecting libmali EGL and GLES" "info"
	local lib_dir="${SDCARD}/usr/lib/aarch64-linux-gnu"
	local library

	# This is the GPU-specific integration used by Armbian's RK3588
	# reComputer target. Bypass GLVND for EGL/GLES so it cannot silently select
	# Mesa llvmpipe while the BSP kbase device is active.
	for library in libEGL.so.1.1.0 libGLESv2.so.2.1.0; do
		rm -f "${lib_dir}/${library}"
	done
	for library in libEGL.so.1 libGLESv2.so.2; do
		rm -f "${lib_dir}/${library}"
		ln -sfn libmali.so.1 "${lib_dir}/${library}"
	done

	install -d "${SDCARD}/usr/share/glvnd/egl_vendor.d"
	printf '%s\n' \
		'{' \
		'    "file_format_version" : "1.0.0",' \
		'    "ICD" : {' \
		'        "library_path" : "libmali.so.1"' \
		'    }' \
		'}' \
		> "${SDCARD}/usr/share/glvnd/egl_vendor.d/00_mali.json"
}

function post_family_tweaks__agibot_mali_gbm_fixup() {
	[[ "${BUILD_DESKTOP}" == "yes" ]] || return 0

	display_alert "${BOARD}" "Selecting the Mali GBM implementation" "info"
	local lib_dir="${SDCARD}/usr/lib/aarch64-linux-gnu"

	chroot_sdcard dpkg-divert --rename \
		--divert /usr/lib/aarch64-linux-gnu/libgbm.so.1.0.0.mesa \
		/usr/lib/aarch64-linux-gnu/libgbm.so.1.0.0 2> /dev/null || true
	rm -f "${lib_dir}/libgbm.so.1"
	ln -sfn mali/libgbm.so.1 "${lib_dir}/libgbm.so.1"
}

function post_family_tweaks__agibot_enable_bluetooth_service() {
	display_alert "${BOARD}" "Enabling rk3588-bluetooth.service" "info"
	chroot_sdcard systemctl enable rk3588-bluetooth.service
	display_alert "${BOARD}" "Enabling agibot-usb-port-power.service" "info"
	chroot_sdcard systemctl enable agibot-usb-port-power.service

	if [[ "${BUILD_DESKTOP}" == "yes" && "${DESKTOP_ENVIRONMENT}" == "gnome" ]]; then
		display_alert "${BOARD}" "Enabling the GNOME display manager" "info"
		chroot_sdcard ln -sfn /lib/systemd/system/gdm3.service \
			/etc/systemd/system/display-manager.service
		chroot_sdcard systemctl set-default graphical.target
	fi
}
