#!/bin/sh
set -u

src="${1:-.}"
fail=0

err() {
	echo "FAIL: $*" >&2
	[ -n "${GITHUB_ACTIONS:-}" ] && echo "::error::$*"
	fail=1
}

need_ym() {
	grep -Eq "^CONFIG_$1=[ym]" "$kcfg" || err "CONFIG_$1 应为 y/m"
}

need_y() {
	grep -qx "CONFIG_$1=y" "$kcfg" || err "CONFIG_$1 应为 y"
}

need_unset() {
	grep -Eq "^CONFIG_$1=[ym]" "$kcfg" && err "CONFIG_$1 不应启用"
}

ppe=$(find "$src/build_dir" -type f -path '*/linux-airoha_an7581*/linux-*/drivers/net/ethernet/airoha/airoha_ppe.c' 2>/dev/null | head -1)
echo "airoha_ppe=$ppe"
if [ -z "$ppe" ]; then
	err "找不到 airoha_ppe.c"
else
	grep -q 'FLOW_ACTION_PPPOE_PUSH' "$ppe" || err "airoha_ppe.c 缺少 FLOW_ACTION_PPPOE_PUSH"
fi

nf=$(find "$src/build_dir" -type f -path '*/linux-airoha_an7581*/linux-*/net/netfilter/nf_flow_table_offload.c' 2>/dev/null | head -1)
echo "nf_flow_table_offload=$nf"
if [ -z "$nf" ]; then
	err "找不到 nf_flow_table_offload.c"
else
	grep -q 'vlan_id' "$nf" || err "nf_flow_table_offload.c 缺少 706-04 VLAN ID 修复"
fi

kcfg=$(find "$src/build_dir" -type f -path '*/linux-airoha_an7581*/linux-*/.config' 2>/dev/null | head -1)
echo "kernel_config=$kcfg"
if [ -z "$kcfg" ]; then
	err "找不到内核 .config"
else
	need_ym NF_FLOW_TABLE
	need_ym NFT_FLOW_OFFLOAD
	need_ym PPPOE
	need_y NET_AIROHA
	need_y NET_AIROHA_NPU
	need_y PCS_AIROHA
	need_y PCS_AIROHA_AN7581
	need_unset NET_AIROHA_FLOW_STATS
fi

for f in en7581_npu_data.bin en7581_npu_rv32.bin; do
	find "$src/staging_dir" -type f -name "$f" -size +0c 2>/dev/null | grep -q . || err "缺少或为空: $f"
done

if [ "$fail" -ne 0 ]; then
	exit 1
fi

echo "PPE/PON 断言通过"
