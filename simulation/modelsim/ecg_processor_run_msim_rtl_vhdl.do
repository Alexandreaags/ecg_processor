transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vcom -93 -work work {/home/alexandre/Documents/github/ecg_processor/ecg_processor.vhd}
vcom -93 -work work {/home/alexandre/Documents/github/ecg_processor/ecg_rom.vhd}
vcom -93 -work work {/home/alexandre/Documents/github/ecg_processor/ssd_decoder.vhd}

