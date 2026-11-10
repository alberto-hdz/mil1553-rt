library ieee;
use ieee.std_logic_1164.all;

entity manchester_enc is
  generic (CLKS_PER_HALF : positive := 25);  -- 50 MHz clock -> 0.5 us half bit
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;
    is_cmd  : in  std_logic;  -- '1' = command/status sync, '0' = data sync
    data_in : in  std_logic_vector(15 downto 0);
    tx      : out std_logic;
    tx_en   : out std_logic;  -- high while driving the bus
    busy    : out std_logic
  );
end entity;

architecture rtl of manchester_enc is
  signal sr      : std_logic_vector(39 downto 0) := (others => '0');  -- 40 half-bits to send
  signal half_ct : natural range 0 to CLKS_PER_HALF - 1 := 0;          -- clocks into current half-bit
  signal left    : natural range 0 to 40 := 0;                         -- half-bits still to send
begin
  process (clk)
    variable p   : std_logic;                       -- parity accumulator
    variable pat : std_logic_vector(39 downto 0);   -- pattern being built
  begin
    if rising_edge(clk) then
      if rst = '1' then
        left    <= 0;
        half_ct <= 0;
      elsif left = 0 then
        if start = '1' then
          -- odd parity: start at '1', XOR in all 16 bits
          p := '1';
          for i in 0 to 15 loop
            p := p xor data_in(i);
          end loop;
          -- sync: 3 us total, polarity depends on word type
          if is_cmd = '1' then
            pat(39 downto 34) := "111000";
          else
            pat(39 downto 34) := "000111";
          end if;
          -- data bits, MSB first: 1 -> "10" (high then low), 0 -> "01"
          for i in 0 to 15 loop
            if data_in(15 - i) = '1' then
              pat(33 - 2*i downto 32 - 2*i) := "10";
            else
              pat(33 - 2*i downto 32 - 2*i) := "01";
            end if;
          end loop;
          -- parity bit goes last
          if p = '1' then
            pat(1 downto 0) := "10";
          else
            pat(1 downto 0) := "01";
          end if;
          sr      <= pat;
          left    <= 40;
          half_ct <= 0;
        end if;
      else
        -- hold each half-bit for CLKS_PER_HALF clocks, then shift to the next
        if half_ct = CLKS_PER_HALF - 1 then
          half_ct <= 0;
          sr      <= sr(38 downto 0) & '0';
          left    <= left - 1;
        else
          half_ct <= half_ct + 1;
        end if;
      end if;
    end if;
  end process;

  tx    <= sr(39) when left /= 0 else '0';
  tx_en <= '1' when left /= 0 else '0';
  busy  <= '1' when left /= 0 else '0';
end architecture;
