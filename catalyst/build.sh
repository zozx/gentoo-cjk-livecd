#!/usr/bin/env bash
set -euo pipefail

echo "===> 1. 更新 Portage Tree..."
emerge-webrsync

echo "===> 2. 安裝 Catalyst 與相關工具..."
cp -r /workspace/catalyst/fsystem/etc .

emerge --verbose --quiet dev-vcs/git dev-util/catalyst sys-fs/squashfs-tools sys-boot/grub net-misc/wget net-misc/curl

echo "===> 3. 拉取 gentoo-zh 與 官方 releng 倉庫..."
mkdir -p /workspace/catalyst/fsystem/var/db/repos/gentoo-zh
git clone --depth 1 https://github.com/gentoo-zh/overlay.git /workspace/catalyst/fsystem/var/db/repos/gentoo-zh
git clone --depth 1 https://github.com/gentoo/releng.git /tmp/releng

echo "===> 4. 定位 Spec 檔案..."
SPEC_DIR="/tmp/releng/releases/specs/amd64"
STAGE1=$(find "$SPEC_DIR" -name "*installcd*stage1*.spec" | head -n 1)
STAGE2=$(find "$SPEC_DIR" -name "*installcd*stage2*.spec" | head -n 1)

if [ -z "$STAGE1" ] || [ -z "$STAGE2" ]; then
  STAGE1=$(find "$SPEC_DIR" -name "*livecd*stage1*.spec" | head -n 1)
  STAGE2=$(find "$SPEC_DIR" -name "*livecd*stage2*.spec" | head -n 1)
fi

echo "[+] Target Stage1 Spec: $STAGE1"
echo "[+] Target Stage2 Spec: $STAGE2"

echo "===> 5. 取得最新 Stage3 種子檔與 TIMESTAMP..."
# 僅提取包含 stage3 與 .tar.xz 的真實路徑行，避免抓到 PGP 簽名標頭（-----BEGIN...）
STAGE3_PATH=$(curl -s https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt | grep -E 'stage3-amd64-openrc-.*\.tar\.xz' | awk '{print $1}' | head -n 1)

if [ -z "$STAGE3_PATH" ]; then
  echo "[!] 錯誤：無法從 Gentoo 鏡像取得 Stage3 路徑！"
  exit 1
fi

STAGE3_TARBALL=$(basename -- "$STAGE3_PATH")
TIMESTAMP=$(echo "$STAGE3_TARBALL" | sed -E 's/stage3-amd64-openrc-(.*)\.tar\.xz/\1/')

echo "[+] Detected Stage3 Timestamp: $TIMESTAMP"

SEED_DIR="/var/tmp/catalyst/builds/23.0-default"
mkdir -p "$SEED_DIR"
wget -q -O "$SEED_DIR/stage3-amd64-openrc-${TIMESTAMP}.tar.xz" \
  "https://distfiles.gentoo.org/releases/amd64/autobuilds/${STAGE3_PATH}"


echo "[+] Detected Stage3 Timestamp: $TIMESTAMP"

SEED_DIR="/var/tmp/catalyst/builds/23.0-default"
mkdir -p "$SEED_DIR"
wget -q -O "$SEED_DIR/stage3-amd64-openrc-${TIMESTAMP}.tar.xz" \
  "https://distfiles.gentoo.org/releases/amd64/autobuilds/${STAGE3_PATH}"

echo "===> 6. 替換 Spec 檔案參數..."
# 替換時間戳記
sed -i "s|@TIMESTAMP@|${TIMESTAMP}|g" "$STAGE1" "$STAGE2"
sed -i "s|@DATESTAMP@|${TIMESTAMP}|g" "$STAGE1" "$STAGE2"

# 替換核心套件
sed -i 's|sys-kernel/gentoo-kernel-bin|sys-kernel/gentoo-cjk-kernel-bin|g' "$STAGE1" "$STAGE2"
sed -i 's|sys-kernel/gentoo-sources|sys-kernel/gentoo-cjk-kernel-bin|g' "$STAGE1" "$STAGE2"
sed -i 's|boot/kernel/gentoo/sources:.*|boot/kernel/gentoo/sources: sys-kernel/gentoo-cjk-kernel-bin|g' "$STAGE2"

# 注入 portage_confdir 與 overlay
echo "portage_confdir: /workspace/catalyst/fsystem/etc/portage" >> "$STAGE1"
echo "portage_confdir: /workspace/catalyst/fsystem/etc/portage" >> "$STAGE2"
echo "livecd/overlay: /workspace/catalyst/fsystem" >> "$STAGE2"

echo "===> 驗證 Stage1 Spec 中的 source_subpath："
grep "source_subpath" "$STAGE1"

echo "===> 7. 執行 Catalyst 構建..."
mkdir -p /var/tmp/catalyst /var/builds
catalyst -s latest

catalyst -f "$STAGE1"
catalyst -f "$STAGE2"

echo "===> 8. 匯出 ISO..."
cp /var/tmp/catalyst/builds/default/*stage2*/*.iso /workspace/gentoo-cjk-minimal.iso
echo "[+] 構建成功！ISO 位置：/workspace/gentoo-cjk-minimal.iso"
