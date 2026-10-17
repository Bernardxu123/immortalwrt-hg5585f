#!/bin/sh
# 生成 HG5585F 专用的 .config。必须在 OpenWrt 源码树根目录执行。
#
# 分层依据（scripts/kconfig.pl 源码语义）：
#   `+ A B` 只接受两个操作数，config_add 按 A→B 顺序写入，
#   后者无条件覆盖前者，**包括 "# CONFIG_X is not set" 覆盖 "CONFIG_X=y"**。
#   所以我们的层必须放在最后一步。链式而不是嵌套表达式，
#   是因为 parse_expr 用 ^\+ 前缀匹配，嵌套写法极易踩成 "Parse error"。
#
# 环境变量：
#   PROXY=none|passwall|openclash   分流层（默认 passwall）
#   ALLOW_NO_INITRAMFS=1            跳过 recovery.itb（CI 超时降级用）
#
# 用法：
#   cd <ponwrt 源码根> && sh scripts/hg5585f/gen-config.sh
# 本地只验证配置层、不编译（Windows 无 perl 时用这个）：
#   python scripts/hg5585f/kmerge.py configs/an7581.config configs/release.config \
#       configs/hg5585f-profile.config configs/hg5585f-build.config \
#       configs/hg5585f-proxy-passwall.config > /tmp/c.cfg
#   python scripts/hg5585f/kmerge.py --check /tmp/c.cfg

set -e

SRC=$(pwd)

if [ ! -x "$SRC/scripts/kconfig.pl" ]; then
	echo "错误：当前目录不是 OpenWrt 源码根（找不到 scripts/kconfig.pl）" >&2
	echo "      当前目录：$SRC" >&2
	exit 1
fi

PROXY="${PROXY:-passwall}"
case "$PROXY" in
none)      PROXY_CFG= ;;
passwall)  PROXY_CFG=configs/hg5585f-proxy-passwall.config ;;
openclash) PROXY_CFG=configs/hg5585f-proxy-openclash.config ;;
*)
	echo "错误：PROXY='$PROXY' 不支持，只能是 none / passwall / openclash" >&2
	exit 1
	;;
esac

for f in configs/an7581.config configs/release.config \
	 configs/hg5585f-profile.config configs/hg5585f-build.config; do
	if [ ! -f "$SRC/$f" ]; then
		echo "错误：缺少 $f" >&2
		exit 1
	fi
done
if [ -n "$PROXY_CFG" ] && [ ! -f "$SRC/$PROXY_CFG" ]; then
	echo "错误：缺少 $PROXY_CFG" >&2
	exit 1
fi

echo "==> [1/5] 上游基线 + 上游包层"
./scripts/kconfig.pl + configs/an7581.config configs/release.config > .config.s1

echo "==> [2/5] 叠加 HG5585F profile 层（12 device -> 2）"
./scripts/kconfig.pl + .config.s1 configs/hg5585f-profile.config > .config.s2

echo "==> [3/5] 叠加 HG5585F build 层（ccache / 能力锚点 / 去 UPnP / 去 EN7572）"
# ALLOW_NO_INITRAMFS=1 时跳过 recovery.itb（CI 撞超时时的降级开关）
if [ "$ALLOW_NO_INITRAMFS" = "1" ]; then
	echo "    ! 已关闭 INITRAMFS（不产出 recovery.itb）"
	sed 's|^CONFIG_TARGET_ROOTFS_INITRAMFS=y|# CONFIG_TARGET_ROOTFS_INITRAMFS is not set|' \
		configs/hg5585f-build.config > .hg5585f-build.config.tmp
	BUILD_CFG=.hg5585f-build.config.tmp
	export SKIP_INITRAMFS_CHECK=1
else
	BUILD_CFG=configs/hg5585f-build.config
fi
./scripts/kconfig.pl + .config.s2 "$BUILD_CFG" > .config.s3

echo "==> [4/5] 叠加分流层：$PROXY"
if [ -n "$PROXY_CFG" ]; then
	./scripts/kconfig.pl + .config.s3 "$PROXY_CFG" > .config
else
	mv .config.s3 .config
fi

rm -f .config.s1 .config.s2 .config.s3 .hg5585f-build.config.tmp

echo "==> [5/5] make defconfig"
make defconfig

# CONFIG_CCACHE_DIR 是 kconfig 字符串，不会展开 $HOME，必须注入绝对路径，
# 否则 ccache 会落到不可预期的目录，CI 缓存命中率归零。
if grep -q '^CONFIG_CCACHE=y' .config; then
	sed -i "s|^CONFIG_CCACHE_DIR=.*|CONFIG_CCACHE_DIR=\"$SRC/.ccache\"|" .config
	echo "    ccache 目录：$SRC/.ccache"
fi

PROXY="$PROXY" sh scripts/hg5585f/assert-config.sh .config

echo "==> .config 生成完成：$(wc -l < .config) 行（PROXY=$PROXY）"
