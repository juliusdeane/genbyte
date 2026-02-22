#!/bin/bash
# Called by DKMS via POST_BUILD after each kernel module build.
# Working directory when invoked is the DKMS build directory (where bytegen.ko lives).
#
# Usage (by DKMS internally): dkms_sign.sh <kernelver>
MODULE_VERSION=1.1

KERNELVER=${1:-$(uname -r)}
SRCDIR="/usr/src/bytegen-${MODULE_VERSION}"
SIGN_FILE="/usr/src/linux-headers-${KERNELVER}/scripts/sign-file"
KEY="${SRCDIR}/MOK.secret"
CERT="${SRCDIR}/MOK.der"

if [ ! -x "$SIGN_FILE" ]; then
    echo "[bytegen DKMS] ERROR: sign-file not found at: $SIGN_FILE"
    echo "[bytegen DKMS] Make sure linux-headers-${KERNELVER} is installed."
    exit 1
fi

if [ -f "$KEY" ] && [ -f "$CERT" ]; then
    "$SIGN_FILE" sha512 "$KEY" "$CERT" bytegen.ko
    echo "[bytegen DKMS] Module signed successfully."
else
    echo "[bytegen DKMS] WARNING: MOK keys not found at ${SRCDIR}/"
    echo "[bytegen DKMS] The module was NOT signed and may not load under Secure Boot."
    echo "[bytegen DKMS] To fix: copy MOK.secret and MOK.der to ${SRCDIR}/ and rebuild."
fi
