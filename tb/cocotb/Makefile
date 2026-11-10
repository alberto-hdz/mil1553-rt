SIM ?= ghdl
TOPLEVEL_LANG = vhdl
GHDL_ARGS = --std=08
RTL = $(PWD)/../../rtl
VHDL_SOURCES = $(RTL)/manchester_enc.vhd
TOPLEVEL = manchester_enc
MODULE = test_enc
export PYTHONPATH := $(PWD)/../../model:$(PYTHONPATH)
include $(shell cocotb-config --makefiles)/Makefile.sim
