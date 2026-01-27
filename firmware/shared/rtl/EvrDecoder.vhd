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
        evrRxUsrClk : in  sl;  -- user clock (rx data interface syncrhonous to this clock)
        evrRxData   : out slv(15 downto 0)
        );
end entity EvrDecoder;

architecture rtl of EvrDecoder is

begin

    -- TODO

end architecture rtl;
