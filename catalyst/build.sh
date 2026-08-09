#!/usr/bin/env bash
set -euo pipefail

echo "===> 0. 建立 Loop 設備節點..."
if [ ! -c /dev/loop-control ]; then
  mknod /dev/loop-control c 10 237
fi
for i in $(seq 0 15); do
  if [ ! -b "/dev/loop$i" ]; then
    mknod -m 0660 "/dev/loop$i" b 7 "$i"
  fi
done

echo "===> 1. 更新 Portage Tree..."
emerge-webrsync

echo "===> 2. 套用基礎 Portage 配置並安裝工具..."
# 先將 package.accept_keywords 等基本配置同步至容器 /etc/
cp -a /workspace/catalyst/fsystem/etc/. /etc/

emerge --verbose --getbinpkg --quiet dev-vcs/git dev-util/catalyst sys-fs/squashfs-tools sys-boot/grub net-misc/wget net-misc/curl

echo "===> 3. 拉取 gentoo-zh 與 官方 releng 倉庫..."
mkdir -p /workspace/catalyst/fsystem/etc/portage/repos/gentoo-zh
if [ ! -d "/workspace/catalyst/fsystem/etc/portage/repos/gentoo-zh/.git" ]; then
  git clone --depth 1 https://github.com/gentoo-zh/overlay.git /workspace/catalyst/fsystem/etc/portage/repos/gentoo-zh
fi
git clone --depth 1 https://github.com/gentoo/releng.git /tmp/releng

# git clone 完成後，將完整的 gentoo-zh 倉庫同步至宿主容器系統的 /etc/portage/repos/
mkdir -p /etc/portage/repos/gentoo-zh
cp -a /workspace/catalyst/fsystem/etc/portage/repos/gentoo-zh/. /etc/portage/repos/gentoo-zh/

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

echo "===> 6. 替換 Spec 檔案參數..."
sed -i "s|@TIMESTAMP@|${TIMESTAMP}|g" "$STAGE1" "$STAGE2"
sed -i "s|@DATESTAMP@|${TIMESTAMP}|g" "$STAGE1" "$STAGE2"
sed -i "s|@TREEISH@|latest|g" "$STAGE1" "$STAGE2"

sed -i 's|sys-kernel/gentoo-kernel-bin|sys-kernel/gentoo-cjk-kernel-bin|g' "$STAGE1" "$STAGE2"
sed -i 's|sys-kernel/gentoo-sources|sys-kernel/gentoo-cjk-kernel-bin|g' "$STAGE1" "$STAGE2"
sed -i 's|boot/kernel/gentoo/sources:.*|boot/kernel/gentoo/sources: sys-kernel/gentoo-cjk-kernel-bin|g' "$STAGE2"

echo "portage_confdir: /workspace/catalyst/fsystem/etc/portage" >> "$STAGE1"
echo "portage_confdir: /workspace/catalyst/fsystem/etc/portage" >> "$STAGE2"
echo "livecd/overlay: /workspace/catalyst/fsystem" >> "$STAGE2"

echo "===> 7. 打包 Portage Tree Snapshot 並執行 Catalyst 構建..."
mkdir -p /var/tmp/catalyst/snapshots /var/tmp/catalyst/builds /var/builds
mksquashfs /var/db/repos/gentoo /var/tmp/catalyst/snapshots/gentoo-latest.sqfs -comp gzip -b 1M

catalyst -f "$STAGE1"
catalyst -f "$STAGE2"

echo "===> 8. 匯出 ISO..."
cp /var/tmp/catalyst/builds/default/*stage2*/*.iso /workspace/gentoo-cjk-minimal.iso
echo "[+] 構建成功！ISO 位置：/workspace/gentoo-cjk-minimal.iso"
