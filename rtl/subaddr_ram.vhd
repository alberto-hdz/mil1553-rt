library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 32 subaddresses x 32 words x 16 bits = one 18Kb block RAM
entity subaddr_ram is
  port (
    clk  : in  std_logic;
    we   : in  std_logic;
    addr : in  std_logic_vector(9 downto 0);  -- subaddress & word index
    din  : in  std_logic_vector(15 downto 0);
    dout : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of subaddr_ram is
  type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
  signal mem : mem_t := (others => (others => '0'));
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        mem(to_integer(unsigned(addr))) <= din;
      end if;
      dout <= mem(to_integer(unsigned(addr)));
    end if;
  end process;
end architecture;
