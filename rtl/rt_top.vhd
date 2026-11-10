library ieee;
use ieee.std_logic_1164.all;

entity rt_top is
  generic (
    RT_ADDR       : natural range 0 to 30 := 5;
    CLKS_PER_HALF : positive := 25  -- 50 MHz clock
  );
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;
    rx_p : in  std_logic;
    rx_n : in  std_logic;
    tx_p : out std_logic;
    tx_n : out std_logic
  );
end entity;

architecture rtl of rt_top is
  signal d_valid, d_cmd, d_perr, d_merr, d_active : std_logic;
  signal d_data                                   : std_logic_vector(15 downto 0);
  signal e_push, e_cmd, e_full, e_busy, tx, tx_en : std_logic;
  signal e_data                                   : std_logic_vector(15 downto 0);
  signal ram_we                                   : std_logic;
  signal ram_addr                                 : std_logic_vector(9 downto 0);
  signal ram_din, ram_dout                        : std_logic_vector(15 downto 0);
begin
  dec : entity work.manchester_dec
    generic map (CLKS_PER_HALF => CLKS_PER_HALF)
    port map (clk => clk, rst => rst, rx_p => rx_p, rx_n => rx_n,
              valid => d_valid, data => d_data, is_cmd => d_cmd,
              perr => d_perr, merr => d_merr, active => d_active);

  core : entity work.rt_core
    generic map (RT_ADDR => RT_ADDR, CLKS_PER_HALF => CLKS_PER_HALF)
    port map (clk => clk, rst => rst,
              d_valid => d_valid, d_data => d_data, d_cmd => d_cmd,
              d_perr => d_perr, d_merr => d_merr, d_active => d_active,
              e_push => e_push, e_data => e_data, e_cmd => e_cmd,
              e_full => e_full, e_busy => e_busy,
              ram_we => ram_we, ram_addr => ram_addr, ram_din => ram_din, ram_dout => ram_dout);

  enc : entity work.manchester_enc
    generic map (CLKS_PER_HALF => CLKS_PER_HALF)
    port map (clk => clk, rst => rst, start => e_push, is_cmd => e_cmd, data_in => e_data,
              tx => tx, tx_en => tx_en, busy => e_busy, full => e_full);

  ram : entity work.subaddr_ram
    port map (clk => clk, we => ram_we, addr => ram_addr, din => ram_din, dout => ram_dout);

  -- two-wire bus like a transceiver interface: idle = both low
  tx_p <= tx and tx_en;
  tx_n <= (not tx) and tx_en;
end architecture;
