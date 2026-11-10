-- manchester_enc.vhd
-- Manchester II encoder for my 1553 RT. Takes a 16-bit word, builds the 40
-- half-bit pattern (3 us sync, data MSB first, odd parity) and shifts it out
-- at 1 Mbps. The holding register lets the next word start on the same clock
-- the current one ends, since words in a 1553 message have to be back to back.

library ieee;
use ieee.std_logic_1164.all;

entity manchester_enc is
  generic (CLKS_PER_HALF : positive := 25);  -- 50 MHz clock -> 0.5 us half bit
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;  -- push a word (accepted when full = '0')
    is_cmd  : in  std_logic;  -- '1' = command/status sync, '0' = data sync
    data_in : in  std_logic_vector(15 downto 0);
    tx      : out std_logic;
    tx_en   : out std_logic;  -- high while driving the bus
    busy    : out std_logic;  -- transmitting or holding a word
    full    : out std_logic   -- holding register occupied
  );
end entity;

architecture rtl of manchester_enc is
  signal sr       : std_logic_vector(39 downto 0) := (others => '0');  -- 40 half-bits to send
  signal half_ct  : natural range 0 to CLKS_PER_HALF - 1 := 0;         -- clocks into current half-bit
  signal left     : natural range 0 to 40 := 0;                        -- half-bits still to send
  signal nxt_data : std_logic_vector(15 downto 0) := (others => '0');  -- holding register
  signal nxt_cmd  : std_logic := '0';
  signal nxt_vld  : std_logic := '0';

  -- 40 half-bit pattern for one word: sync, 16 data bits MSB first, odd parity
  function build(d : std_logic_vector(15 downto 0); c : std_logic) return std_logic_vector is
    variable p   : std_logic := '1';
    variable pat : std_logic_vector(39 downto 0);
  begin
    for i in 0 to 15 loop
      p := p xor d(i);
    end loop;
    if c = '1' then
      pat(39 downto 34) := "111000";
    else
      pat(39 downto 34) := "000111";
    end if;
    for i in 0 to 15 loop
      if d(15 - i) = '1' then
        pat(33 - 2*i downto 32 - 2*i) := "10";
      else
        pat(33 - 2*i downto 32 - 2*i) := "01";
      end if;
    end loop;
    if p = '1' then
      pat(1 downto 0) := "10";
    else
      pat(1 downto 0) := "01";
    end if;
    return pat;
  end function;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        left    <= 0;
        half_ct <= 0;
        nxt_vld <= '0';
      else
        -- accept a pushed word into the holding register
        if start = '1' and nxt_vld = '0' then
          nxt_data <= data_in;
          nxt_cmd  <= is_cmd;
          nxt_vld  <= '1';
        end if;

        if left = 0 then
          -- idle: start the held word right away
          if nxt_vld = '1' then
            sr      <= build(nxt_data, nxt_cmd);
            left    <= 40;
            half_ct <= 0;
            nxt_vld <= '0';
          end if;
        elsif half_ct = CLKS_PER_HALF - 1 then
          half_ct <= 0;
          if left = 1 and nxt_vld = '1' then
            -- last half-bit done: start the held word with no gap (words are contiguous)
            sr      <= build(nxt_data, nxt_cmd);
            left    <= 40;
            nxt_vld <= '0';
          else
            sr   <= sr(38 downto 0) & '0';
            left <= left - 1;
          end if;
        else
          half_ct <= half_ct + 1;
        end if;
      end if;
    end if;
  end process;

  tx    <= sr(39) when left /= 0 else '0';
  tx_en <= '1' when left /= 0 else '0';
  busy  <= '1' when left /= 0 or nxt_vld = '1' else '0';
  full  <= nxt_vld;
end architecture;
