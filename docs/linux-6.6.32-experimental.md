# Linux 6.6.32 QNAP Driver Experiment

## Status

This is an upstream-kernel build experiment, not a confirmed QNAP-compatible
release.

On August 17, 2026, the Realtek driver was compiled successfully against a
fully built upstream Linux 6.6.32 tree and packaged as a separate experimental
QPKG. No installation or runtime test has yet been completed on QNAP hardware.

The stable project path remains QNAP kernel `5.10.60-qnap`.

## What was verified

- Realtek source: v2.21.4, commit
  `67fc21ca514c2a8e3555070001295397e0dbc84b`
- Kernel source: upstream Linux 6.6.32
- Compiler: GCC 13.3.0
- `CONFIG_LOCALVERSION="-qnap"`
- `CONFIG_NR_CPUS=32`
- `CONFIG_PINCTRL=y`
- `CONFIG_MODVERSIONS` disabled
- `r8152.c` was not modified
- RTL8159 `0bda:815a` was already present in the upstream USB table
- `RTL8152_S5_WOL` remained disabled
- The module compiled after a complete kernel build generated
  `Module.symvers`

The resulting module reports:

```text
version:    v2.21.4 (2025/10/28)
srcversion: 1A03B3E3C8B337AB1CB6DFA
vermagic:   6.6.32-qnap SMP preempt mod_unload
```

It includes all three RTL8159 aliases:

```text
usb:v0BDAp815Ad*dc*dsc*dp*ic02isc0Dip00in*
usb:v0BDAp815Ad*dc*dsc*dp*ic02isc06ip00in*
usb:v0BDAp815Ad*dc*dsc*dp*icFFisc*ip*in*
```

## Source integrity

The source hashes were identical before and after compilation:

```text
13868f24c70c8f7901affda7cdd8c7f23fc2b897b0159b79f66ce6800a94ea25  r8152.c
b5bfcb0913ed25b7f8041cdad2bdb159f2a35c45f73f5c044acd733b03653224  Makefile
```

This is different from the stable 5.10 build path, whose compatibility function
currently rewrites `strscpy` and enables `RTL8152_S5_WOL`.

## Why a full kernel build was required

`make modules_prepare` alone did not generate `Module.symvers`. The first
external-module attempt stopped at modpost with more than 140 unresolved kernel
symbols.

A complete upstream kernel build generated `Module.symvers`, after which the
external Realtek module compiled successfully. This confirms upstream 6.6.32
source compatibility, but it does not provide QNAP's symbol CRCs or kernel ABI.

## Experimental QPKG

The local experiment produced:

```text
RTL8159_6_6_Exp_2.21.4e66_x86_64.qpkg
```

The package uses the distinct QPKG name `RTL8159_6_6_Exp`, so it does not
upgrade or overwrite the stable `RTL8159_Driver` package.

Build identities:

```text
Module SHA256:
192c64b6e28669ac360e43c757c565cf66c7dac9d33aa968d68237f8bb6a90db

QPKG SHA256:
565fc43e5e975e77551c535d45ff2c3cd1bc78cdcf220d48e10d976c8bbee86c
```

The generated QPKG is a build artifact and is intentionally excluded by
`.gitignore`.

## Safety behavior

The experimental package reuses the validated service and QDK lifecycle logic:

- requires `x86_64`;
- requires `uname -r` to equal the module's kernel vermagic token;
- identifies the stock module by path, vermagic, and srcversion before replacing
  it;
- verifies the loaded QPKG module by srcversion;
- restores the verified stock module if QPKG loading fails;
- blocks package deletion if a verified fallback cannot be restored;
- never writes the experimental module into `/lib/modules`.

Disable the stable package before testing the experimental package. Do not keep
both enabled.

## What remains unverified

The following claims cannot be made without artifacts from the exact QNAP
firmware or a hardware test:

- QNAP's real 6.6.32 `.config`, generated headers, and `Module.symvers`;
- structure layouts for `struct module`, USB, `net_device`, `sk_buff`,
  `urb`, and other inlined kernel ABI;
- QNAP-specific symbol implementations or CRCs;
- module-signing, RANDSTRUCT, BTF, retpoline, and preemption compatibility;
- successful load, device detection, traffic, suspend/shutdown behavior, and
  reboot persistence;
- the exact identity of QNAP's stock v2.19.2 module.

Matching vermagic and successful `insmod` do not prove complete ABI
compatibility. A module can load and still destabilize the kernel because of
structure-layout or inline-code differences.

## Hardware validation procedure

Use only a non-production NAS with backups and a recovery or console path.

Before installation:

```sh
uname -m
uname -r
modinfo -n r8152
modinfo r8152 | grep -E '^(version|srcversion|vermagic):'
cat /sys/module/r8152/srcversion 2>/dev/null
```

Proceed only when:

- `uname -m` is `x86_64`;
- `uname -r` is exactly `6.6.32-qnap`;
- the stock `r8152.ko` can be located and inspected.

After installing the experimental QPKG:

```sh
EXP_PATH=$(/sbin/getcfg "RTL8159_6_6_Exp" Install_Path -f /etc/config/qpkg.conf)
"$EXP_PATH/RTL8159_6_6_Exp.sh" status

modinfo "$EXP_PATH/r8152.ko" | grep -E '^(version|srcversion|vermagic):'
cat /sys/module/r8152/version
cat /sys/module/r8152/srcversion

FILE_SRC=$(modinfo -F srcversion "$EXP_PATH/r8152.ko")
LOADED_SRC=$(cat /sys/module/r8152/srcversion)
[ "$FILE_SRC" = "$LOADED_SRC" ] && echo "QPKG module verified" || echo "NOT the QPKG module"

lsusb | grep -i '0bda:815a'
ip -br link
dmesg | tail -100 | grep -iE 'r8152|rtl8159|unknown symbol|invalid module|verification'
```

Then test traffic and reboot once. Repeat the srcversion, interface, dmesg, and
traffic checks after reboot.

If the test fails, collect:

```sh
EXP_PATH=$(/sbin/getcfg "RTL8159_6_6_Exp" Install_Path -f /etc/config/qpkg.conf)
cat "$EXP_PATH/install.log" 2>/dev/null
dmesg | tail -200
lsmod | grep r8152
cat /sys/module/r8152/srcversion 2>/dev/null
modinfo r8152
```

Do not manually delete the QPKG directory if guarded removal fails. Preserve the
module and logs for diagnosis.

## Conclusion

The experiment proves that unmodified Realtek v2.21.4 source can be compiled and
packaged against a fully built upstream Linux 6.6.32 kernel with GCC 13.

It does not yet prove that the module supports a QNAP Linux 6 system. That claim
requires an exact-QNAP build or successful hardware validation.
