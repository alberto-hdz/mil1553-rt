# Run every testbench:  make test
# Recipe lines start with '>' instead of a tab so copy/paste can't break them.
.RECIPEPREFIX = >

COCOTB = tb/cocotb
CHECK  = python3 tools/check_results.py $(COCOTB)/results.xml

.PHONY: test test-enc test-dec test-rt clean

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

clean:
> rm -rf $(COCOTB)/sim_build $(COCOTB)/results.xml
