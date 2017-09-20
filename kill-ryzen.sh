#!/usr/bin/env bash
export LANG=C

USE_RAMDISK=false
USE_TMPFS=true
CLEAN_ON_EXIT=false
NPROC=$1
TPROC=$2

[ -n "$NPROC" ] || NPROC=$(nproc)
[ -n "$TPROC" ] || TPROC=1

cleanup() {
  if $USE_RAMDISK; then
    sudo rm -rf /mnt/ramdisk/*
    sudo umount /mnt/ramdisk
  elif $USE_TMPFS; then
    cd ..
    sudo umount workdir
  fi
}
if $CLEAN_ON_EXIT; then
  trap "cleanup" SIGHUP SIGINT SIGTERM EXIT
fi

echo "Install required packages"
if which apt-get &>/dev/null; then
 sudo apt-get install build-essential
elif which dnf &>/dev/null; then
 sudo dnf install -y @development-tools
elif which pkg &>/dev/null; then
 sudo pkg install mpfr mpc gmp
else
 exit 1
fi

echo "Download GCC sources"
[ -f gcc-7.1.0.tar.bz2 ] || wget https://ftp.gnu.org/gnu/gcc/gcc-7.1.0/gcc-7.1.0.tar.bz2 || exit 1
export GCCDIR="$PWD"

if $USE_RAMDISK; then
  echo "Create compressed ramdisk"
  sudo mkdir -p /mnt/ramdisk || exit 1
  sudo modprobe zram num_devices=1 || exit 1
  echo 64G | sudo tee /sys/block/zram0/disksize || exit 1
  sudo mkfs.ext4 -q -m 0 -b 4096 -O sparse_super -L zram /dev/zram0 || exit 1
  sudo mount -o relatime,nosuid,discard /dev/zram0 /mnt/ramdisk/ || exit 1
  sudo mkdir -p /mnt/ramdisk/workdir || exit 1
  sudo chmod 777 /mnt/ramdisk/workdir || exit 1
  cp buildloop.sh /mnt/ramdisk/workdir/buildloop.sh || exit 1
  cd /mnt/ramdisk/workdir || exit 1
  mkdir tmpdir || exit 1
  export TMPDIR="$PWD/tmpdir"
elif $USE_TMPFS; then
  mkdir -p workdir || exit 1
  if ( mount | grep -q workdir ); then
    sudo umount workdir
  fi
  sudo mount -t tmpfs tmpfs workdir || exit 1
  cp buildloop.sh workdir/ || exit 1
  cd workdir || exit 1
  mkdir tmpdir || exit 1
  export TMPDIR="$PWD/tmpdir"
fi

echo "Extract GCC sources"
tar xf "$GCCDIR/gcc-7.1.0.tar.bz2" || exit 1

echo "Download prerequisites"
#(cd gcc-7.1.0/ && ./contrib/download_prerequisites)

[ -d 'buildloop.d' ] && rm -r 'buildloop.d'
mkdir -p buildloop.d || exit 1

#echo "cat /proc/cpuinfo | grep -i -E \"(model name|microcode)\""
#cat /proc/cpuinfo | grep -i -E "(model name|microcode)"
echo "sudo dmidecode -t memory | grep -i -E \"(rank|speed|part)\" | grep -v -i unknown"
sudo dmidecode -t memory | grep -i -E "(rank|speed|part)" | grep -v -i unknown
echo "uname -a"
uname -a
#echo "cat /proc/sys/kernel/randomize_va_space"
#cat /proc/sys/kernel/randomize_va_space

# start journal process in different working directory
#pushd /
#  journalctl -kf | sed 's/^/[KERN] /' &
#popd
echo "Using ${NPROC} parallel processes"

START=$(date +%s)
for ((I=0;$I<$NPROC;I++)); do
  (./buildloop.sh "loop-$I" "$TPROC" || echo "TIME TO FAIL: $(($(date +%s)-${START})) s") | sed "s/^/\[loop-${I}\] /" &
  sleep 1
done

wait
