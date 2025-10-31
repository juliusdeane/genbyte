/* ***************************************************************************

Author: Julius Deane <cloud-svc@juliusdeane.com>
AKA: Román Ramírez <rramirez@rootedcon.com>
License: Apache 2.0

Hope you find this tool useful :)

Quick use:
$ make
$ make key
$ make sign
$ make install
$ sudo insmod bytegen
...
$ sudo rmmod bytegen

* ************************************************************************* */
#include <linux/module.h>  // Dynamic module dev.
#include <linux/kernel.h>  // Kernel dev.

#include <linux/fs.h>       // File capabilities
#include <linux/cdev.h>     // Char device API
#include <linux/device.h>   // Create nodes in /dev
#include <asm/uaccess.h>    // copy_to_user


#define DRIVER_NAME   "bytegen"
#define DEVICE_COUNT  256        // 0x00 to 0xFF
#define DEBUG         0          // NO DEBUG, by default. Set to 1 to enable.


// Global structs and variables.
static dev_t bytegen_dev_number;
static struct class *bytegen_class;
static struct cdev bytegen_cdev;

/*****************************************************************************
 * BEGIN module logic:
 *****************************************************************************/
/**
 * This is a callback that will be invoked when create_class is successful.
 */
static int bytegen_uevent(const struct device *dev, struct kobj_uevent_env *env) {
    // THIS SETS PERMS TO: mask=0444 (r--r--r--)
    add_uevent_var(env, "DEVMODE=%#o", 0444);
    return 0;
}

/*****************************************************************************
 * file_operations:
 *****************************************************************************/
/**
 * @brief Read method for the device.
 *
 * Just emits the particular byte associated with the device.
 */
static ssize_t bytegen_read(struct file *filp, char __user *buf, size_t count, loff_t *f_pos) {
    // Get byte from MINOR number.
    // Use: MINOR(filp->f_inode->i_rdev) to retrieve the minor number.
    unsigned char byte_to_emit = MINOR(filp->f_inode->i_rdev);
    ssize_t bytes_sent = 0;

    // Emit byte count number of times.
    while (bytes_sent < count) {
        // Send the byte to userspace.
        if (copy_to_user(buf + bytes_sent, &byte_to_emit, 1))
            return -EFAULT; // POINTER ERROR.

        bytes_sent++;
    }

    return bytes_sent; // Returns actual byte sent count
}


// OPEN
static int bytegen_open(struct inode *inode, struct file *file) {
    /*
       If you want to DEBUG bytegen device uses, you can set DEBUG to 1 (see on top).
    */
#if DEBUG == 1
	printk(KERN_INFO "[bytegen]: OPEN => byte 0x%x\n", MINOR(inode->i_rdev));
#endif
    return 0;
}

// RELEASE
static int bytegen_release(struct inode *inode, struct file *file) {
#if DEBUG == 1
    printk(KERN_INFO "[bytegen]: CLOSE => byte 0x%x\n", MINOR(inode->i_rdev));
#endif
    return 0;
}

// STRUCT to link operations with our local functions.
static const struct file_operations bytegen_fops = {
    .owner   = THIS_MODULE,
    .open    = bytegen_open,
    .release = bytegen_release,
    .read    = bytegen_read,
    // NO WRITE, read only device.
};

/*****************************************************************************
 * MODULE INITILIZATION:
 *****************************************************************************/
static int __init bytegen_init(void) {
    int i;              // index for our 256 devices.
    int ret;            // return value for INIT.
    char dev_name[10];  // Device name like: 0x00, 0xFF, ...

    // 1. Dynamic MAJOR NUMBER and 256 minor numbers.
    ret = alloc_chrdev_region(&bytegen_dev_number, 0, DEVICE_COUNT, DRIVER_NAME);
    if (ret < 0) {
        printk(KERN_ERR "[bytegen]: FAILURE in device number assign :-? : %d\n", ret);

        return ret;
    }

    // 2. UDEV: create a class to manage dynamic devices.
    bytegen_class = class_create(DRIVER_NAME);
    if (IS_ERR(bytegen_class)) {
        printk(KERN_ERR "[bytegen]: FAILURE creating device class :-?\n");
        unregister_chrdev_region(bytegen_dev_number, DEVICE_COUNT);

        return PTR_ERR(bytegen_class);
    }
	// Set the callback.
	bytegen_class->dev_uevent = bytegen_uevent;

    // 3. INIT udev struct.
    cdev_init(&bytegen_cdev, &bytegen_fops);
    bytegen_cdev.owner = THIS_MODULE;
    ret = cdev_add(&bytegen_cdev, bytegen_dev_number, DEVICE_COUNT);
    if (ret < 0) {
        printk(KERN_ERR "[bytegen]: FAILURE adding cdev: %d\n", ret);
        class_destroy(bytegen_class);
        unregister_chrdev_region(bytegen_dev_number, DEVICE_COUNT);

        return ret;
    }

    // 4. Create 256 nodes for devices at: /dev/bytegen/0x<byte>
    for (i = 0; i < DEVICE_COUNT; i++) {
        // Format: "0x00", "0x01", ..., "0xff"
        snprintf(dev_name, sizeof(dev_name), "%#04x", i);

        // Device route will be: /dev/bytegen/0x<byte> (two characters)
        // - MINOR NUMBER will be the byte to emit.
        if (IS_ERR(device_create(bytegen_class, NULL, MKDEV(MAJOR(bytegen_dev_number), i),
                                 NULL, DRIVER_NAME "/%s", dev_name))) {
            printk(KERN_WARNING "[bytegen]: FAILURE, cannot create device for 0x%x\n", i);
        }
    }

    printk(KERN_INFO "[bytegen]: SUCCESS, byte generator loaded. MAJOR: %d. Nodes at /dev/%s/0x00..0xff\n",
           MAJOR(bytegen_dev_number),
           DRIVER_NAME
    );

    return 0;
}

static void __exit bytegen_exit(void) {
    int i;

    // Remove all nodes.
    for (i = 0; i < DEVICE_COUNT; i++) {
        device_destroy(bytegen_class, MKDEV(MAJOR(bytegen_dev_number), i));
    }

    // Remove cdev
    cdev_del(&bytegen_cdev);

    // Destroy class (remove /sys/class/bytegen)
    class_destroy(bytegen_class);

    // Release MAJOR and MINOR numbers.
    unregister_chrdev_region(bytegen_dev_number, DEVICE_COUNT);

    printk(KERN_INFO "[bytegen]: byte generator UNLOADED [OK].\n");
}

module_init(bytegen_init);
module_exit(bytegen_exit);
/*****************************************************************************
 * //END module logic.
 *****************************************************************************/

/* ***************************************************************************
WARNING:
 Because of TAINT mode and compatibility, we cannot use Apache 2.0 license for
the module in kernel space :( It is supposed Apache license is GPL-compatible,
BUT there are minor discrepancies.

So, no way to use Apache 2 as a license here.
* ************************************************************************* */
MODULE_ALIAS("dev:bytegen");
MODULE_VERSION("1.0");

// MODULE_LICENSE("APACHE 2.0");  // NOPE
MODULE_LICENSE("GPL");

MODULE_AUTHOR("Julius Deane <cloud-svc@juliusdeane.com>");
MODULE_DESCRIPTION("Character device to emit a byte based in its name.");
