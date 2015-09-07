--------------------------------------------------------------------------------------------
Build sdcard image:
	1. tf card boot
	(1)cb_build_card_image (compile code to prepare cb_install_tfcard)
	(2)cb_part_install_tfcard dev_label [pack]
		dev_label:      sdb sdc sdd ...
		pack:           the parameter mean we will make a img for dd or win32writer
                cmd for example: cb_part_install_tfcard sdb pack
	(3)cb_install_tfcard  dev_label [pack]
		dev_label:      sdb sdc sdd ...
		pack:           the parameter mean we will make a img for dd or win32writer
                cmd for example: cb_install_tfcard sdb

        2. emmc card boot
	(1)cb_build_flash_card_image (compile code to prepare cb_install_flash_card)
	(2)cb_part_install_flash_card dev_label [pack]
		dev_label:      sdb sdc sdd ...
		pack:           the parameter mean we will make a img for dd or win32writer
                cmd for example: cb_part_install_flash_card sdb pack
	(3)cb_install_flash_card dev_label [pack]
               (install TF card to flash img to emmc)
		dev_label:      sdb sdc sdd ...
		pack:           the parameter mean we will make a img for dd or win32writer
		cmd for example: cb_install_flash_card sdb
---------------------------------------------------------------------------------------------
