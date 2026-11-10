# MIL-STD-1553B Remote Terminal
# Recipe lines start with '>' instead of a tab so copy/paste can't break them.
.RECIPEPREFIX = >

COCOTB = tb/cocotb
CHECK  = python3 tools/check_results.py $(COCOTB)/results.xml

.PHONY: help test test-enc test-dec test-rt waveform clean

help:
> @echo "make test       run every testbench (encoder, decoder, RT)"
> @echo "make test-enc   encoder tests only"
> @echo "make test-dec   decoder tests only"
> @echo "make test-rt    RT system tests only"
> @echo "make waveform   simulate one message and redraw docs/waveform.png"
> @echo "make clean      delete simulation output"

test: test-enc test-dec test-rt
> @echo "All testbenches passed"

test-enc:
> $(MAKE) -C $(COCOTB) TOPLEVEL=manchester_enc MODULE=test_enc
> $(CHECK)

test-dec:
> $(MAKE) -C $(COCOTB) TOPLEVEL=manchester_dec MODULE=test_dec
> $(CHECK)

test-rt:
> $(MAKE) -C $(COCOTB) TOPLEVEL=rt_top MODULE=test_rt
> $(CHECK)

waveform:
> $(MAKE) -C $(COCOTB) TOPLEVEL=rt_top MODULE=capture_waveform
> $(CHECK)
> python3 tools/plot_waveform.py docs/waveform.json docs/waveform.png

clean:
> rm -rf $(COCOTB)/sim_build $(COCOTB)/results.xml docs/waveform.json
