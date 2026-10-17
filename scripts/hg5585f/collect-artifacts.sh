#!/bin/sh
# 收集并校验编译产物。
#
# 三重校验的目的：这个仓库能编 2 个机型，但"编出来了"和"编的是对的那个"是两件事。
# 上游如果改了 DTS 引用、或者我们的 profile 层被 defconfig 推翻，
# 会得到一个文件名对、DTB 错的镜像——刷进去就是砖。
#   1) profiles.json 里必须恰好 2 个 device（防 profile 层失效）
#   2) 每个 device 必须有 sysupgrade 镜像（防 IMAGES 被改）
#   3) 镜像里 strings 能搜到对应 DTB 的 model 字符串（防 DTS 引用错）
#
# 用法：
#   sh scripts/hg5585f/collect-artifacts.sh <源码根> <输出目录>

set -e

SRC="${1:?用法: collect-artifacts.sh <源码根> <输出目录>}"
OUT="${2:?用法: collect-artifacts.sh <源码根> <输出目录>}"
BIN="$SRC/bin/targets/airoha/an7581"

fail() {
	[ -n "$GITHUB_ACTIONS" ] && echo "::error::$*"
	echo "FAIL: $*" >&2
	exit 1
}

[ -d "$BIN" ] || fail "找不到产物目录 $BIN"
mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# 1) profiles.json 必须只有 2 个 device
# ---------------------------------------------------------------------------
PROFILES="$BIN/profiles.json"
[ -f "$PROFILES" ] || fail "找不到 $PROFILES"

python3 - "$PROFILES" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1]) as fh:
    data = json.load(fh)

got = sorted(data.get("profiles", {}).keys())
expect = ["fiberhome_hg5585f-ct", "fiberhome_hg5585f-cu"]
if got != expect:
    print(f"FAIL: profiles.json 里的 device = {got}，期望 {expect}", file=sys.stderr)
    print("      -> configs/hg5585f-profile.config 的收敛层没生效，检查 make defconfig 后的断言", file=sys.stderr)
    sys.exit(1)

print(f"OK: profiles.json 只有 {len(got)} 个 device: {' '.join(got)}")
PY

# ---------------------------------------------------------------------------
# 2) + 3) 每个 device 都要有 sysupgrade 镜像，且 DTB model 对得上
# ---------------------------------------------------------------------------
for dev in cu ct; do
	model="FiberHome HG5585F $(echo "$dev" | tr '[:lower:]' '[:upper:]')"

	images=$(find "$BIN" -maxdepth 1 -type f -name "*hg5585f-${dev}*" | sort)
	[ -n "$images" ] || fail "没有找到 hg5585f-${dev} 的任何镜像（产物目录里只有：$(ls "$BIN" | tr '\n' ' ')）"

	sysup=$(echo "$images" | grep 'sysupgrade' | head -n 1)
	[ -n "$sysup" ] || fail "hg5585f-${dev} 没有 sysupgrade 镜像（只有：$(echo "$images" | xargs -n1 basename | tr '\n' ' ')）"
	[ -f "$sysup" ] || fail "hg5585f-${dev} 的 sysupgrade 镜像路径无效：$sysup"

	if strings "$sysup" | grep -qF "$model"; then
		echo "OK: hg5585f-${dev} sysupgrade 里的 DTB model = \"$model\""
	else
		fail "hg5585f-${dev} 的 sysupgrade 里搜不到 DTB model \"$model\"（DTB 可能引错了）"
	fi

	# 复制该 device 的全部镜像（sysupgrade + recovery）
	for f in $images; do
		cp -f "$f" "$OUT/"
		echo "    + $(basename "$f")  ($(wc -c < "$f") 字节)"
	done
done

# ---------------------------------------------------------------------------
# 附带文件：profile 清单、编译配置、内核版本
# ---------------------------------------------------------------------------
for extra in profiles.json config.buildinfo; do
	[ -f "$BIN/$extra" ] && cp -f "$BIN/$extra" "$OUT/" && echo "    + $extra"
done

# 完整 .config 一起带上，方便复现
[ -f "$SRC/.config" ] && cp -f "$SRC/.config" "$OUT/config.full" && echo "    + config.full"

# ---------------------------------------------------------------------------
# 校验和
# ---------------------------------------------------------------------------
(
	cd "$OUT"
	sha256sum ./* 2>/dev/null | grep -v 'sha256sums.txt' > sha256sums.txt
)

echo ""
echo "产物清单（$OUT）："
ls -lh "$OUT" | sed 's/^/    /'
echo ""
cat "$OUT/sha256sums.txt" | sed 's/^/    /'
