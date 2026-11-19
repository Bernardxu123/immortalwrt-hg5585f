#!/bin/sh

cfg="${1:-.config}"
fail=0

if [ ! -f "$cfg" ]; then
	echo "错误：找不到 $cfg" >&2
	exit 1
fi

err() {
	[ -n "$GITHUB_ACTIONS" ] && echo "::error::$*"
	echo "FAIL: $*" >&2
	fail=1
}

need_y() {
	grep -qx "CONFIG_$1=y" "$cfg" || err "CONFIG_$1 应为 y（实际：$(grep -m1 "^#\? \?CONFIG_$1[= ]" "$cfg" || echo 未出现)）"
}

need_unset() {
	if grep -qx "CONFIG_$1=y" "$cfg"; then
		err "CONFIG_$1 不应为 y"
	elif grep -qx "CONFIG_$1=m" "$cfg"; then
		err "CONFIG_$1 不应为 m"
	fi
}

count=$(grep -c '^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_.*=y$' "$cfg" || true)
if [ "$count" -ne 2 ]; then
	err "device profile 数量 = $count，期望 2。实际启用：$(grep '^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_.*=y$' "$cfg" | sed 's/.*_DEVICE_//;s/=y//' | tr '\n' ' ')"
fi

need_y TARGET_MULTI_PROFILE
need_y TARGET_PER_DEVICE_ROOTFS

need_y TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-cu
need_y TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct

need_y PACKAGE_firewall4
need_y PACKAGE_dnsmasq-full
need_y PACKAGE_odhcpd-ipv6only
need_y PACKAGE_ppp
need_y PACKAGE_ppp-mod-pppoe
need_y PACKAGE_kmod-pppoe

need_y PACKAGE_kmod-nf-conntrack-bridge
need_y PACKAGE_kmod-nf-flow
need_y PACKAGE_kmod-nft-bridge
need_y PACKAGE_kmod-nft-offload

need_unset PACKAGE_kmod-br-netfilter

need_unset PACKAGE_luci-app-upnp
need_unset PACKAGE_miniupnpd-nftables

need_y PACKAGE_kmod-airoha-xpon
need_y PACKAGE_airoha-ponctl
need_y PACKAGE_airoha-pond
need_y PACKAGE_luci-app-pon
need_y PACKAGE_airoha-en7581-npu-firmware
need_unset PACKAGE_kmod-airoha-en7572

need_y PACKAGE_kmod-mt7915e
need_y PACKAGE_kmod-mt7916-firmware

need_y PACKAGE_ethtool-full
need_y PACKAGE_ip-full

[ "$SKIP_INITRAMFS_CHECK" = "1" ] || need_y TARGET_ROOTFS_INITRAMFS
need_y TARGET_ROOTFS_SQUASHFS
need_y CCACHE
need_y PACKAGE_zram-swap

need_unset TARGET_airoha_an7583
need_unset TARGET_airoha_en7523

case "${PROXY:-honk}" in
passwall)
	need_y PACKAGE_luci-app-passwall
	need_y PACKAGE_luci-app-passwall_INCLUDE_Xray
	need_y PACKAGE_luci-app-passwall_INCLUDE_SingBox
	need_y PACKAGE_luci-app-passwall_INCLUDE_Hysteria
	need_unset PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client
	need_unset PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Server
	need_unset PACKAGE_luci-app-openclash
	;;
openclash)
	need_y PACKAGE_luci-app-openclash
	need_unset PACKAGE_luci-app-passwall
	;;
none)
	need_unset PACKAGE_luci-app-passwall
	need_unset PACKAGE_luci-app-openclash
	;;
dae)
	need_y PACKAGE_dae
	need_y PACKAGE_luci-app-dae
	need_y PACKAGE_luci-i18n-dae-zh-cn
	need_y PACKAGE_kmod-sched-core
	need_y PACKAGE_kmod-sched-bpf
	need_y PACKAGE_kmod-veth
	need_y PACKAGE_v2ray-geoip
	need_y PACKAGE_v2ray-geosite
	need_y DAE_USE_KERNEL_BTF
	need_unset DAE_USE_VMLINUX_BTF
	need_unset PACKAGE_luci-app-passwall
	need_unset PACKAGE_luci-app-openclash
	need_unset PACKAGE_xray-core
	need_unset PACKAGE_sing-box
	need_unset PACKAGE_hysteria
	;;
honk)
	need_y PACKAGE_honk
	need_y PACKAGE_luci-app-honk
	need_y PACKAGE_luci-lib-daeuniverse
	need_y PACKAGE_luci-i18n-daeuniverse-zh-cn
	need_y PACKAGE_vmlinux-btf-builtin
	need_y PACKAGE_kmod-sched-core
	need_y PACKAGE_kmod-sched-bpf
	need_y PACKAGE_kmod-veth
	need_y PACKAGE_kmod-nft-core
	need_y PACKAGE_kmod-nft-queue
	need_y PACKAGE_kmod-nfnetlink-queue
	need_y PACKAGE_kmod-nf-conntrack
	need_y PACKAGE_v2ray-geoip
	need_y PACKAGE_v2ray-geosite
	need_y PACKAGE_ca-bundle
	need_unset PACKAGE_dae
	need_unset PACKAGE_luci-app-dae
	need_unset PACKAGE_luci-i18n-dae-zh-cn
	need_unset PACKAGE_luci-app-passwall
	need_unset PACKAGE_luci-app-openclash
	need_unset PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client
	need_unset PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Server
	need_unset PACKAGE_xray-core
	need_unset PACKAGE_sing-box
	need_unset PACKAGE_hysteria
	;;
*)
	err "PROXY='${PROXY}' 不支持（none|passwall|openclash|dae|honk）"
	;;
esac

if [ "${PROXY:-honk}" = "dae" ] || [ "${PROXY:-honk}" = "honk" ]; then
	need_y KERNEL_DEBUG_INFO
	need_unset KERNEL_DEBUG_INFO_REDUCED
	need_y KERNEL_DEBUG_INFO_BTF
	need_y KERNEL_BPF_EVENTS
	need_y KERNEL_CGROUP_BPF
	need_y KERNEL_XDP_SOCKETS
	need_y KERNEL_KPROBES
	need_y KERNEL_NETKIT
fi

if [ "$fail" -ne 0 ]; then
	echo "" >&2
	echo "配置断言失败。常见原因与修法：" >&2
	echo "  * device 数量不对 -> configs/hg5585f-profile.config 被上游覆盖，检查是否出现新的 device profile" >&2
	echo "  * 关键包丢失    -> 上游改了包名或 DEFAULT_PACKAGES，需要同步 configs/hg5585f-build.config" >&2
	echo "  * br_netfilter  -> 有包 select 了 kmod-br-netfilter，检查上游 kmod 依赖变化" >&2
	echo "  * 分流包缺失    -> feeds 没装全，或上游改了 luci-app-passwall 的 INCLUDE_ 符号名" >&2
	exit 1
fi

echo "配置断言通过：2 个 device profile（cu/ct）、关键包齐备、未装 br_netfilter、分流=${PROXY:-honk}"
