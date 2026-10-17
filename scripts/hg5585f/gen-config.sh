#!/bin/sh
# 生成 HG5585F 专用的 .config。必须在 OpenWrt 源码树根目录执行。
#
# 分层依据（scripts/kconfig.pl 源码语义）：
#   `+ A B` 只接受两个操作数，config_add 按 A→B 顺序写入，
#   后者无条件覆盖前者，**包括 "# CONFIG_X is not set" 覆盖 "CONFIG_X=y"**。
#   所以我们的层必须放在最后一步。三步链式而不是嵌套表达式，
#   是因为 parse_expr 用 ^\+ 前缀匹配，嵌套写法极易踩成 "Parse error"。
#
# 用法：
#   cd <ponwrt 源码根> && sh scripts/hg5585f/gen-config.sh
# 或者本地干跑（不需要 make / 编译器）：
#   python scripts/hg5585f/kmerge.py configs/an7581.config configs/release.config \
#       configs/hg5585f-profile.config configs/hg5585f-build.config | \
#       python scripts/hg5585f/kmerge.py --check /dev/stdin

set -e

SRC=$(pwd)

if [ ! -x "$SRC/scripts/kconfig.pl" ]; then
	echo "错误：当前目录不是 OpenWrt 源码根（找不到 scripts/kconfig.pl）" >&2
	echo "      当前目录：$SRC" >&2
	exit 1
fi

for f in configs/an7581.config configs/release.config \
	 configs/hg5585f-profile.config configs/hg5585f-build.config; do
	if [ ! -f "$SRC/$f" ]; then
		echo "错误：缺少 $f" >&2
		exit 1
	fi
done

echo "==> [1/4] 上游基线 + 上游包层"
./scripts/kconfig.pl + configs/an7581.config configs/release.config > .config.s1

echo "==> [2/4] 叠加 HG5585F profile 层（12 device -> 2）"
./scripts/kconfig.pl + .config.s1 configs/hg5585f-profile.config > .config.s2

echo "==> [3/4] 叠加 HG5585F build 层（ccache / 能力锚点 / offload 依赖）"
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
./scripts/kconfig.pl + .config.s2 "$BUILD_CFG" > .config

rm -f .config.s1 .config.s2 .hg5585f-build.config.tmp

echo "==> [4/4] make defconfig"
make defconfig

# CONFIG_CCACHE_DIR 是 kconfig 字符串，不会展开 $HOME，必须注入绝对路径，
# 否则 ccache 会落到不可预期的目录，CI 缓存命中率归零。
if grep -q '^CONFIG_CCACHE=y' .config; then
	sed -i "s|^CONFIG_CCACHE_DIR=.*|CONFIG_CCACHE_DIR=\"$SRC/.ccache\"|" .config
	echo "    ccache 目录：$SRC/.ccache"
fi

sh scripts/hg5585f/assert-config.sh .config

echo "==> .config 生成完成：$(wc -l < .config) 行"
