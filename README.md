# Genbyte project

Maybe you are used to something like:

```shell
$ dd if=/dev/zero of=file.img
```

This is quite powerful in *ix systems, as it is a quick way of creating a binary file full of nothing (null bytes). But, what if I want to do the same but using a different "byte" value, for example, *0x41*?

This is the main purpose of this kernel module :)

## PRE-requisites

To be able to load a module in kernels linked to Secure Boot you will need to enroll a MOK (*Machine Owner Key*). So, please, take on mind the process may not be comfortable if you are not used to it.

> Whenever the kernel is updated, yes, it will require a re-compilation and signing with the MOK key.

## Basic usage

Once the dynamic module is installed (for example, to `/lib/modules/<kernel version>/extra/bytegen.ko` or `/lib/modules/<kernel version>/updates/bytegen.ko`):

```shell
$ sudo insmod bytegen
```

Or:

```shell
$ sudo modprobe bytegen
```

Just verify it is loaded:

```shell
$ lsmod | grep bytegen
bytegen                12288  0
```

And now the module is ready to be used.


> !!!!! Pay attention here, I mean it !!!!!
>
> **VERY IMPORTANT**: the moment the kernel version changes, the moment you will need to rebuild the module and load again. See the [DKMS section](#dkms-automatic-rebuild-on-kernel-updates) below to automate this.


## /dev/bytegen/

The module, once compiled, signed and loaded, will create a subdirectory within `/dev` named `bytegen` and, within this one, **256 character devices** with the names of the particular byte they will emit:

```shell
$ ls /dev/bytegen
0x00  0x09  0x12  0x1b  0x24  0x2d  0x36  0x3f  0x48  0x51  0x5a  0x63  0x6c  0x75  0x7e  0x87  0x90  0x99  0xa2  0xab  0xb4  0xbd  0xc6  0xcf  0xd8  0xe1  0xea  0xf3  0xfc
0x01  0x0a  0x13  0x1c  0x25  0x2e  0x37  0x40  0x49  0x52  0x5b  0x64  0x6d  0x76  0x7f  0x88  0x91  0x9a  0xa3  0xac  0xb5  0xbe  0xc7  0xd0  0xd9  0xe2  0xeb  0xf4  0xfd
0x02  0x0b  0x14  0x1d  0x26  0x2f  0x38  0x41  0x4a  0x53  0x5c  0x65  0x6e  0x77  0x80  0x89  0x92  0x9b  0xa4  0xad  0xb6  0xbf  0xc8  0xd1  0xda  0xe3  0xec  0xf5  0xfe
0x03  0x0c  0x15  0x1e  0x27  0x30  0x39  0x42  0x4b  0x54  0x5d  0x66  0x6f  0x78  0x81  0x8a  0x93  0x9c  0xa5  0xae  0xb7  0xc0  0xc9  0xd2  0xdb  0xe4  0xed  0xf6  0xff
0x04  0x0d  0x16  0x1f  0x28  0x31  0x3a  0x43  0x4c  0x55  0x5e  0x67  0x70  0x79  0x82  0x8b  0x94  0x9d  0xa6  0xaf  0xb8  0xc1  0xca  0xd3  0xdc  0xe5  0xee  0xf7
0x05  0x0e  0x17  0x20  0x29  0x32  0x3b  0x44  0x4d  0x56  0x5f  0x68  0x71  0x7a  0x83  0x8c  0x95  0x9e  0xa7  0xb0  0xb9  0xc2  0xcb  0xd4  0xdd  0xe6  0xef  0xf8
0x06  0x0f  0x18  0x21  0x2a  0x33  0x3c  0x45  0x4e  0x57  0x60  0x69  0x72  0x7b  0x84  0x8d  0x96  0x9f  0xa8  0xb1  0xba  0xc3  0xcc  0xd5  0xde  0xe7  0xf0  0xf9
0x07  0x10  0x19  0x22  0x2b  0x34  0x3d  0x46  0x4f  0x58  0x61  0x6a  0x73  0x7c  0x85  0x8e  0x97  0xa0  0xa9  0xb2  0xbb  0xc4  0xcd  0xd6  0xdf  0xe8  0xf1  0xfa
0x08  0x11  0x1a  0x23  0x2c  0x35  0x3e  0x47  0x50  0x59  0x62  0x6b  0x74  0x7d  0x86  0x8f  0x98  0xa1  0xaa  0xb3  0xbc  0xc5  0xce  0xd7  0xe0  0xe9  0xf2  0xfb
```

Now, using one of these char devices, you can just issue:


```shell
$ sudo dd if=/dev/bytegen/0x41 bs=1 count=10
AAAAAAAAAA10+0 registros leídos
10+0 registros escritos
10 bytes copied, 2,9249e-05 s, 342 kB/s
```

Or:

```shell
$ sudo dd if=/dev/bytegen/0x41 bs=32 count=1
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1+0 registros leídos
1+0 registros escritos
32 bytes copied, 1,2725e-05 s, 2,5 MB/s
```

Or:

```shell
$ sudo dd if=/dev/bytegen/0x42 bs=32 count=1
BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB1+0 registros leídos
1+0 registros escritos
32 bytes copied, 1,2715e-05 s, 2,5 MB/s
```

So now you can just generate arbitrary byte values with a character device just using this virtual device :)


### Hey, why not just use `tr`?

Yes, you can just use the standard `/dev/zero` and then perform a translation from *0* to whatever the byte you need, but what about researching and playing with stuff? 


## Use it without root privileges

This is the very first question you may want to ask :) We changed the code to use a callback that will set read permissions for anyone. Look at the callback:

```c++
static int bytegen_uevent(const struct device *dev, struct kobj_uevent_env *env) {
    // THIS SETS PERMS TO: mask=0444 (r--r--r--)
    add_uevent_var(env, "DEVMODE=%#o", 0444);
    return 0;
}
```

With the `0444` mask, every user in the system will be able to use the character devices.

### Controlling access via module parameter

The permission behaviour is controlled by the `allow_all_users` module parameter (default: `1`). No recompilation is needed — just pass it at load time:

```shell
# Open to all users (default):
$ sudo modprobe bytegen

# Restrict to root only:
$ sudo modprobe bytegen allow_all_users=0
```

You can inspect the current value at any time while the module is loaded:

```shell
$ cat /sys/module/bytegen/parameters/allow_all_users
1
```

You can also check the parameter description via `modinfo`:

```shell
$ modinfo bytegen | grep allow_all_users
parm:           allow_all_users:If 1 (default), all users can read devices. If 0, root only. (int)
```

# WORKING WITH THE MODULE

Build process, if you know about building and loading kernel modules, will have some complex steps. I tried to prepare the `Makefile` to be easy to use (I hope). 

## 1. Build

It is supposed it will just need:

```shell
$ make build
```

## 2. Sign

If you have UEFI/Secure Boot in your machine, it is almost certain that you will not be able to load kernel modules that are not signed by an authorized key. So, please, pay attention to this section.

Having signing keys (take a look into the `Makefile` if you already have your own ***MOK keys***):

```shell
$ make sign
```

If not, you need to create (*generate*) them:

```shell
$ make generate_key
```

And install your new keys to be used:

```shell
$ make install_key
```

In the process of installing the key, please, **be careful** and pay attention to the instructions. A password will be requested and, then, a reboot for the Secure Boot to enroll the new key.

> If you do not follow those steps, your key will not be recognized by the system thus the module will not be able to load.

This is a requirement to prevent arbitrary modules to be loaded in innocent users machines, making the kernel trust a new key using the Secure Boot.

The module will be signed using kernel helper tool:

```shell
$ /usr/src/linux-headers-$(shell uname -r)/scripts/sign-file sha512 MOK.secret MOK.der bytegen.ko
```

You may change `Makefile` to use `kmodsign` directly:

```shell
$ kmodsign sha512 MOK.secret MOK.der bytegen.ko
```

## 3. Install

```shell
$ make install
```

## 4. Load

```shell
$ make load
```

And finally, use it:

```shell
$ dd if=/dev/bytegen/0x44 bs=1 count=32
DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD32+0 records in
32+0 records out
32 bytes copied, 4.9783e-05 s, 643 kB/s
```


## DKMS: automatic rebuild on kernel updates

Without DKMS, every kernel update breaks the module and requires a manual rebuild, re-sign, and reinstall. DKMS automates all of that.

### Prerequisites

```shell
$ sudo apt install dkms linux-headers-$(uname -r)
```

### Register with DKMS

This copies the sources and MOK signing keys to `/usr/src/bytegen-1.1/`, registers the module, and performs the first build and install:

```shell
$ make dkms_add
```

> **Secure Boot**: if `MOK.secret` and `MOK.der` are present in the project directory, they are copied automatically and used to sign the module after every DKMS rebuild. If they are missing, the module will build but not be signed — it will fail to load on Secure Boot systems.

From this point on, whenever a new kernel is installed via `apt`, DKMS rebuilds and signs `bytegen.ko` automatically before the next reboot.

### Check DKMS status

```shell
$ make dkms_status
bytegen/1.1, 6.8.0-90-generic, x86_64: installed
```

### Remove from DKMS

```shell
$ make dkms_remove
```

This unregisters the module from DKMS and removes the sources from `/usr/src/bytegen-1.1/`.
