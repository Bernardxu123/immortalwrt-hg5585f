#!/bin/sh
# .config 断言：make defconfig 之后立刻跑，30 秒失败，省掉 3 小时白烧。
#
# 为什么要它：
#   make defconfig 会为"没写进 .config 的符号"填默认值。如果上游把某个 device
#   profile 加进了 ALL_PROFILES，或者把 DEFAULT_PACKAGES 改了，我们的收敛层可能
#   被悄悄推翻——那时镜像里会多出 10 个用不上的机型，构建时间翻倍，
#   甚至可能把不想要的内核模块带进来。断言能在编译开始前把这类问题拦下来。
#
# 用法：
#   sh scripts/hg5585f/assert-config.sh .config

cfg="${1:-.config}"
fail=0

if [ ! -f "$cfg" ]; then
	echo "错误：找不到 $cfg" >&2
	exit 1
fi

err() {
	# GitHub Actions 里输出成 annotation，本地就是普通文本
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

# ---- 1. device profile 必须恰好 2 个 ----
count=$(grep -c '^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_.*=y$' "$cfg" || true)
if [ "$count" -ne 2 ]; then
	err "device profile 数量 = $count，期望 2。实际启用：$(grep '^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_.*=y$' "$cfg" | sed 's/.*_DEVICE_//;s/=y//' | tr '\n' ' ')"
fi

# ---- 2. 多 profile 机制本身 ----
need_y TARGET_MULTI_PROFILE
need_y TARGET_PER_DEVICE_ROOTFS

# ---- 3. 两台机器的 profile ----
need_y TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-cu
need_y TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct

# ---- 4. 路由能力（用户要求"保留完整路由能力"，随时能顶替主路由拨号）----
need_y PACKAGE_firewall4
need_y PACKAGE_dnsmasq-full
need_y PACKAGE_odhcpd-ipv6only
need_y PACKAGE_ppp
need_y PACKAGE_ppp-mod-pppoe
need_y PACKAGE_kmod-pppoe

# ---- 5. 桥接 flow offload 依赖链 ----
# conntrack-bridge 提供 nf_conntrack_bridge.ko，是 fw4 bridge-family flowtable
# （ponwrt 自带 001-add-bridge-flowtable-support.patch）能卸载桥接流量的前提。
need_y PACKAGE_kmod-nf-conntrack-bridge
need_y PACKAGE_kmod-nf-flow
need_y PACKAGE_kmod-nft-bridge
need_y PACKAGE_kmod-nft-offload

# ---- 6. 不能装 br_netfilter ----
# 它才是"桥接帧进 iptables"的元凶，跟 nf_conntrack_bridge 是两回事。
need_unset PACKAGE_kmod-br-netfilter

# ---- 6b. 不装 UPnP ----
# 2026-10-17 miniupnpd 2.3.11 的 feed 补丁已失效，且代理出口不需要 UPnP。
need_unset PACKAGE_luci-app-upnp
need_unset PACKAGE_miniupnpd-nftables

# ---- 7. PON 栈 ----
need_y PACKAGE_kmod-airoha-xpon
need_y PACKAGE_airoha-ponctl
need_y PACKAGE_airoha-pond
need_y PACKAGE_luci-app-pon
# HG5585F 用 paged BOSA；EN7572 前端对它是多余驱动+固件
need_unset PACKAGE_kmod-airoha-en7572

# ---- 8. WiFi 硬件保留 ----
need_y PACKAGE_kmod-mt7915e
need_y PACKAGE_kmod-mt7916-firmware

# ---- 9. 运维工具（pon-watchdog 与排障要用）----
need_y PACKAGE_ethtool-full
need_y PACKAGE_ip-full

# ---- 10. 镜像形态 ----
# INITRAMFS 是 CI 超时时的降级开关，SKIP_INITRAMFS_CHECK=1 时跳过
[ "$SKIP_INITRAMFS_CHECK" = "1" ] || need_y TARGET_ROOTFS_INITRAMFS
need_y TARGET_ROOTFS_SQUASHFS
need_y CCACHE
need_y PACKAGE_zram-swap

# ---- 11. 不参与的 subtarget ----
need_unset TARGET_airoha_an7583
need_unset TARGET_airoha_en7523

# ---- 12. 分流层（由 gen-config.sh 通过 PROXY 传入，默认 honk）----
case "${PROXY:-honk}" in
passwall)
	need_y PACKAGE_luci-app-passwall
	need_y PACKAGE_luci-app-passwall_INCLUDE_Xray
	need_y PACKAGE_luci-app-passwall_INCLUDE_SingBox
	need_y PACKAGE_luci-app-passwall_INCLUDE_Hysteria
	# Rust 工具链会让构建时间翻倍，明确不要
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
	# dae 的 BTF 来源必须锁内核 BTF（ponwrt 主树没有 vmlinux-btf 虚包）
	need_y DAE_USE_KERNEL_BTF
	need_unset DAE_USE_VMLINUX_BTF
	# "只保留一种代理"
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
	# honk 和 dae 互斥（dae0/daens 同名）
	need_unset PACKAGE_dae
	need_unset PACKAGE_luci-app-dae
	need_unset PACKAGE_luci-i18n-dae-zh-cn
	# "只保留一种代理"
	need_unset PACKAGE_luci-app-passwall
	need_unset PACKAGE_luci-app-openclash
	# 不把 Rust 工具链拉进构建（上游 an7581.config 默认开了这两个）
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

# ---- 13. eBPF 数据面的 BTF 依赖链（PROXY=dae|honk 时逐项验证）----
# 这一组全部是"静默失败"型：符号丢了不报错，只是 BTF 不生成、dae/honk 起不来。
# 依赖链（任一项不满足，DEBUG_INFO_BTF 都会被 kconfig 悄悄丢弃）：
#   KERNEL_DEBUG_INFO=y
#   KERNEL_DEBUG_INFO_REDUCED 必须 not set
#   KERNEL_DEBUG_INFO_BTF=y
#   + 核心层 DEBUG_INFO_DWARF4=y（由 an7581/config-6.18 保证，不在 .config 里）
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
