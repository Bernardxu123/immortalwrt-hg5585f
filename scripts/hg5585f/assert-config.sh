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

if [ "$fail" -ne 0 ]; then
	echo "" >&2
	echo "配置断言失败。常见原因与修法：" >&2
	echo "  * device 数量不对 -> configs/hg5585f-profile.config 被上游覆盖，检查是否出现新的 device profile" >&2
	echo "  * 关键包丢失    -> 上游改了包名或 DEFAULT_PACKAGES，需要同步 configs/hg5585f-build.config" >&2
	echo "  * br_netfilter  -> 有包 select 了 kmod-br-netfilter，检查上游 kmod 依赖变化" >&2
	exit 1
fi

echo "配置断言通过：2 个 device profile（cu/ct）、关键包齐备、未装 br_netfilter"
