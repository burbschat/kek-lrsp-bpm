library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;

entity EvrDecoder is
    -- Consume (rx) event system data, all syncrhonous to usr clock and extract
    -- event code/shared bus.
    port (
        evrRxUsrClk  : in sl;  -- user clock (rx data interface syncrhonous to this clock)
        evrRxData    : in slv(15 downto 0);
        evrRxDataK   : in slv(1 downto 0);
        evrRxDispErr : in slv(1 downto 0);
        evrRxDecErr  : in slv(1 downto 0)
        );
end entity EvrDecoder;

architecture rtl of EvrDecoder is

begin

    RX_PROC : process(evrRxUsrClk)
    begin
        if rising_edge(evrRxUsrClk) then
        -- TODO
        end if;
    end process RX_PROC;

end architecture rtl;
