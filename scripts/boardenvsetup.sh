#!/bin/bash
#

cb_build_linux()
{
    if [ ! -d ${CB_KBUILD_DIR} ]; then
    mkdir -pv ${CB_KBUILD_DIR}
    fi

    echo "Start Building linux"
	cp -v ${CB_PRODUCT_DIR}/kernel_defconfig ${CB_KSRC_DIR}/arch/arm/configs/
	cp ${CB_KSRC_DIR}/arch/arm/configs/kernel_defconfig ${CB_KSRC_DIR}/.config
	make -C ${CB_KSRC_DIR}  ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j6 INSTALL_MOD_PATH=${CB_TARGET_DIR}  uImage modules
	rm -rf ${CB_KSRC_DIR}/arch/arm/configs/kernel_defconfig
    echo "Build linux successfully"
}

cb_build_card_image()
{
    cb_build_linux
	sudo rm ${CB_OUTPUT_DIR}/card0-part2/ -fr
	make -C ${CB_KSRC_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} INSTALL_FW_PATH=${CB_OUTPUT_DIR}/card0-part2/lib/firmware -j8 firmware_install
    make -C ${CB_KSRC_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j4 INSTALL_MOD_PATH=${CB_OUTPUT_DIR}/card0-part2 modules_install
	(cd ${CB_PRODUCT_DIR}/overlay; tar -c *) | tar -C ${CB_OUTPUT_DIR}/card0-part2  -x --no-same-owner
		if [ -e ${CB_OUTPUT_DIR}/card0-part2/root/boot-file ]; then
			cp -v  ${CB_PRODUCT_DIR}/sys_config.fex  ${CB_OUTPUT_DIR}/card0-part2/root/boot-file
		fi

	(cd ${CB_OUTPUT_DIR}/card0-part2; tar -c * )|gzip -9 > ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
	cat  ${CB_TOOLS_DIR}/scripts/readme.txt

}

cb_part_sd_a80()
{

    local card="$1"
	local Part1Size=24576
    if cb_sd_check $card
    then
	echo "Cleaning /dev/$card"
    else
	return 1
    fi

    sudo sfdisk -R /dev/$card
    sudo sfdisk --force --in-order -uS /dev/$card <<EOF
40960,${Part1Size},L
,,L
EOF

    sync
    
    sudo mkfs.vfat /dev/${card}1
    sudo mkfs.ext4 /dev/${card}2

    return 0
}

cb_part_sd_pack_a80()
{

    local card="$1"
	local Part1Size=24576
	local Part2Size=2097152
    if cb_sd_check $card
    then
	echo "Cleaning /dev/$card"
    else
	return 1
    fi

	Part2Size=$(expr $2 + $Part1Size)
	echo $Part2Size
    sudo sfdisk -R /dev/$card
    sudo sfdisk --force --in-order -uS /dev/$card <<EOF
40960,${Part1Size},L
,${Part2Size},L
EOF

    sync

    sudo mkfs.vfat /dev/${card}1
    sudo mkfs.ext4 /dev/${card}2

    return 0
}

cb_make_boot_a80()
{
	local   sd_dev=$1
	cp -v ${CB_U_BOOT_SPL_BIN} ${CB_U_BOOT_SPL_BIN_OUTPUT}
	cp -v ${CB_U_BOOT_BIN} ${CB_U_BOOT_BIN_OUTPUT}
	cp -v ${CB_U_BOOT_MMC2_BIN} ${CB_U_BOOT_MMC2_BIN_OUTPUT}
	cp ${CB_PRODUCT_DIR}/sys_config.fex ${CB_OUTPUT_DIR}
	cd ${CB_OUTPUT_DIR}
	busybox unix2dos ${CB_OUTPUT_DIR}/sys_config.fex
	cubie-fex2bin ${CB_OUTPUT_DIR}/sys_config.fex ${CB_OUTPUT_DIR}/sys_config.bin
	cubie-uboot-spl ${CB_U_BOOT_SPL_BIN} ${CB_OUTPUT_DIR}/sys_config.bin ${CB_U_BOOT_SPL_BIN_OUTPUT}
	cubie-uboot ${CB_U_BOOT_BIN} ${CB_OUTPUT_DIR}/sys_config.bin ${CB_U_BOOT_BIN_OUTPUT}
	cubie-uboot ${CB_U_BOOT_MMC2_BIN} ${CB_OUTPUT_DIR}/sys_config.bin ${CB_U_BOOT_MMC2_BIN_OUTPUT}
	cd -
	echo "script done"
	sudo dd if=${CB_U_BOOT_SPL_BIN_OUTPUT} of=/dev/${sd_dev} bs=1024 seek=8
	sudo dd if=${CB_U_BOOT_BIN_OUTPUT} of=/dev/${sd_dev} bs=1024 seek=19096
	sync
	cd ${CB_SDK_ROOTDIR}
}

cb_part_install_tfcard()
{
	local   sd_dev=$1
	local	pack_install="install"
	echo "$1 $2 !"
	if [ $# -eq 2 ]; then
		if [ $2 = "pack" ];then
			pack_install="pack"
			local	RootfsSizeKB=$(expr $CB_ROOTFS_SIZE \* 1024  +  100 \* 1024)
			local	PartExt4=$(expr $RootfsSizeKB + $RootfsSizeKB / 10)
			local	PartSize=$(expr $PartExt4 \* 2)
			if cb_part_sd_pack_a80 ${sd_dev} ${PartSize}
    		then
    		echo "Make sunxi partitons successfully"
    		else
    		echo "Make sunxi partitions failed"
    		return 1
    		fi
		else
			echo "the 2 parameter only support [pack] now !"
		fi
	else
		if cb_part_sd_a80 ${sd_dev}
    	then
    	echo "Make sunxi partitons successfully"
    	else
    	echo "Make sunxi partitions failed"
    	return 1
    	fi
	fi
}

cb_install_tfcard()
{
	local   sd_dev=$1
	local	pack_install="install"
	echo "$1 $2 !"
	if [ $# -eq 2 ]; then
		if [ $2 = "pack" ];then
			pack_install="pack"
			local	RootfsSizeKB=$(expr $CB_ROOTFS_SIZE \* 1024  +  100 \* 1024)
			local	PartExt4=$(expr $RootfsSizeKB + $RootfsSizeKB / 10)
			local	PartSize=$(expr $PartExt4 \* 2)
		else
			echo "the 2 parameter only support [pack] now !"
		fi
	fi

	cb_make_boot_a80 ${sd_dev}
#	exit 1
	mkdir -pv ${CB_OUTPUT_DIR}/part1 ${CB_OUTPUT_DIR}/part2
	sudo mount /dev/${sd_dev}1 ${CB_OUTPUT_DIR}/part1
	sudo cp ${CB_KSRC_DIR}/arch/arm/boot/uImage ${CB_OUTPUT_DIR}/part1
	sync
	sudo umount ${CB_OUTPUT_DIR}/part1
	sudo mount /dev/${sd_dev}2 ${CB_OUTPUT_DIR}/part2
	sudo tar -C ${CB_OUTPUT_DIR}/part2 --strip-components=1 -zxpf ${CB_ROOTFS_IMAGE}
	sync
	sudo tar -C ${CB_OUTPUT_DIR}/part2 -zxpf ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
	sync

	if [ $pack_install = "pack" ]; then
		sudo cp ${CB_PRODUCT_DIR}/firstrun_pack ${CB_OUTPUT_DIR}/part2/etc/init.d/firstrun
		sudo cp ${CB_PRODUCT_DIR}/rcS ${CB_OUTPUT_DIR}/part2/etc/init.d/rcS
		sudo chmod +x ${CB_OUTPUT_DIR}/part2/etc/init.d/firstrun
		sudo chmod +x ${CB_OUTPUT_DIR}/part2/etc/init.d/rcS
		sudo touch ${CB_OUTPUT_DIR}/part2/root/firstrun
	fi
	sync
	if [ $pack_install = "pack" ]; then
		ddSize=$(expr $PartExt4 / 1024 + 100)
		echo "card size must larger than $ddSize !"
		sudo dd if=/dev/${sd_dev} of=${CB_OUTPUT_DIR}/${CB_BOARD_NAME}-${CB_SYSTEM_NAME}-tfcard.img bs=1M count=$ddSize
	fi
	sync
	sudo umount ${CB_OUTPUT_DIR}/part2
	sudo rm -fr ${CB_OUTPUT_DIR}/part1 ${CB_OUTPUT_DIR}/part2
}

cb_build_flash_card_image()
{
    cb_build_linux
	sudo rm ${CB_OUTPUT_DIR}/card0-part2/ -fr
	if [ -e ${CB_OUTPUT_DIR}/rootfs ] ; then
		sudo umount ${CB_OUTPUT_DIR}/rootfs
		sudo rm ${CB_OUTPUT_DIR}/rootfs -fr
	fi
	make -C ${CB_KSRC_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} INSTALL_FW_PATH=${CB_OUTPUT_DIR}/card0-part2/lib/firmware -j8 firmware_install
    make -C ${CB_KSRC_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j4 INSTALL_MOD_PATH=${CB_OUTPUT_DIR}/card0-part2 modules_install
	(cd ${CB_PRODUCT_DIR}/overlay; tar -c *) | tar -C ${CB_OUTPUT_DIR}/card0-part2  -x --no-same-owner
		if [ -e ${CB_OUTPUT_DIR}/card0-part2/root/boot-file ]; then
			cp -v  ${CB_PRODUCT_DIR}/sys_config.fex  ${CB_OUTPUT_DIR}/card0-part2/root/boot-file
		fi
	mkdir  -pv ${CB_OUTPUT_DIR}/card0-part2/lib/modules/3.4.39/extra/
	chmod +x ${CB_KSRC_DIR}/modules/rogue_km/binary_sunxi_linux_xorg_release/target_armhf/*.ko
	cp ${CB_KSRC_DIR}/modules/rogue_km/binary_sunxi_linux_xorg_release/target_armhf/*.ko ${CB_OUTPUT_DIR}/card0-part2/lib/modules/3.4.39/extra/

	(cd ${CB_OUTPUT_DIR}/card0-part2; tar -c * )|gzip -9 > ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
	CB_ROOTFS_SIZE_TO_DD=$(expr ${CB_ROOTFS_SIZE} + ${CB_ROOTFS_SIZE} / 4)
	sudo dd if=/dev/zero of=${CB_OUTPUT_DIR}/rootfs.ext4 bs=1M count=${CB_ROOTFS_SIZE_TO_DD}
	echo y | sudo mkfs.ext4 -i 8192 ${CB_OUTPUT_DIR}/rootfs.ext4


	mkdir ${CB_OUTPUT_DIR}/rootfs
	sudo mount ${CB_OUTPUT_DIR}/rootfs.ext4 ${CB_OUTPUT_DIR}/rootfs
	sudo tar -C ${CB_OUTPUT_DIR}/rootfs --strip-components=1 -zxpf ${CB_ROOTFS_IMAGE}
	sync
	sudo tar -C ${CB_OUTPUT_DIR}/rootfs -zxpf ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
	sudo cp ${CB_PRODUCT_DIR}/firstrun  ${CB_OUTPUT_DIR}/rootfs/etc/init.d/firstrun
	sudo cp ${CB_PRODUCT_DIR}/rcS  ${CB_OUTPUT_DIR}/rootfs/etc/init.d/rcS
	sudo chmod +x  ${CB_OUTPUT_DIR}/rootfs/etc/init.d/firstrun
	sudo chmod +x  ${CB_OUTPUT_DIR}/rootfs/etc/init.d/rcS
	sudo touch  ${CB_OUTPUT_DIR}/rootfs/root/firstrun
	sync
	(cd ${CB_OUTPUT_DIR}/rootfs;  sudo tar -cp *) |gzip -9 > ${CB_OUTPUT_DIR}/rootfs.tar.gz
	cd ${CB_SDK_ROOTDIR}
	sync
	sudo umount ${CB_OUTPUT_DIR}/rootfs
	rm ${CB_OUTPUT_DIR}/rootfs -fr
	cat  ${CB_TOOLS_DIR}/scripts/readme.txt

}

cb_part_install_flash_card()
{
	local   sd_dev=$1
	echo "$1"
	local sizeByte=$(sudo du -sb ${CB_OUTPUT_DIR}/rootfs.tar.gz | awk '{print $1}')
#	sizeBytetgz=$(sudo du -sb ${CB_ROOTFS_IMAGE} | awk '{print $1}')
	local RootfsSizeKB=$(expr $sizeByte / 1000 + $CB_FLASH_TSD_ROOTFS_SIZE \* 1024 +  50 \* 1024)
	local PartExt4=$(expr $RootfsSizeKB + $RootfsSizeKB / 10)
	local PartSize=$(expr $PartExt4 \* 2)
	echo "PartSize=${PartSize}  sizeByte=${PartExt4}"
	sudo umount ${CB_OUTPUT_DIR}/rootfs
	rm ${CB_OUTPUT_DIR}/rootfs
	if cb_part_sd_pack_a80 ${sd_dev} ${PartSize}
	then
    echo "Make sunxi partitons successfully"
    else
    echo "Make sunxi partitions failed"
    return 1
    fi
}

cb_install_flash_card()
{
	local   sd_dev=$1
	local	pack_install="install"
	echo "$1 $2 !"
	if [ $# -eq 2 ]; then
		if [ $2 = "pack" ];then
			pack_install="pack"
		else
			echo "the 2 parameter only support [pack] now !"
		fi
	fi

	local sizeByte=$(sudo du -sb ${CB_OUTPUT_DIR}/rootfs.tar.gz | awk '{print $1}')
#	sizeBytetgz=$(sudo du -sb ${CB_ROOTFS_IMAGE} | awk '{print $1}')
	local RootfsSizeKB=$(expr $sizeByte / 1000 + $CB_FLASH_TSD_ROOTFS_SIZE \* 1024 +  50 \* 1024)
	local PartExt4=$(expr $RootfsSizeKB + $RootfsSizeKB / 10)
	local PartSize=$(expr $PartExt4 \* 2)
	echo "PartSize=${PartSize}  sizeByte=${PartExt4}"

	cb_make_boot_a80 ${sd_dev}
	mkdir -pv ${CB_OUTPUT_DIR}/part1 ${CB_OUTPUT_DIR}/part2
	sudo mount /dev/${sd_dev}1 ${CB_OUTPUT_DIR}/part1
	sudo cp ${CB_KSRC_DIR}/arch/arm/boot/uImage ${CB_OUTPUT_DIR}/part1
	sync
	sudo umount ${CB_OUTPUT_DIR}/part1
	sudo mount /dev/${sd_dev}2 ${CB_OUTPUT_DIR}/part2
	sudo tar -C ${CB_OUTPUT_DIR}/part2 -zxpf ${CB_FLASH_ROOTFS_IMAGE}
	sync
	sudo cp -v ${CB_OUTPUT_DIR}/rootfs.tar.gz  ${CB_OUTPUT_DIR}/part2/rootfs.tar.gz
	sudo cp -v ${CB_PRODUCT_DIR}/install.sh ${CB_OUTPUT_DIR}/part2/bin
	sudo cp -v ${CB_KSRC_DIR}/arch/arm/boot/uImage ${CB_OUTPUT_DIR}/part2
	sudo chmod +x ${CB_OUTPUT_DIR}/part2/bin/install.sh
	sudo cp ${CB_U_BOOT_SPL_BIN_OUTPUT} ${CB_OUTPUT_DIR}/part2/u-boot-spl.bin
	sudo cp ${CB_U_BOOT_MMC2_BIN_OUTPUT} ${CB_OUTPUT_DIR}/part2/u-boot.bin
	sync

	if [ $pack_install = "pack" ]; then
		ddSize=$(expr $PartExt4 / 1024 + 100)
		echo "card size must larger than $ddSize !"
		sudo dd if=/dev/${sd_dev} of=${CB_OUTPUT_DIR}/${CB_SYSTEM_NAME}-tf_flash_emmc.img bs=1M count=$ddSize
	fi

	sync
	sudo umount ${CB_OUTPUT_DIR}/part2
	sudo rm -fr ${CB_OUTPUT_DIR}/part1 ${CB_OUTPUT_DIR}/part2

}
