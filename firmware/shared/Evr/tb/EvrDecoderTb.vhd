library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;

library work;
use work.AppPkg.all;

entity EvrDecoderTb is end EvrDecoderTb;

architecture testbed of EvrDecoderTb is

    constant DATA_CLK_PERIOD_C : time := 8.753501400560225 ns;  -- 1/114.24MHz
    constant AXI_CLK_PERIOD_C  : time := 10.0 ns;               -- 1/114.24MHz
    constant TPD_C             : time := 1 ns;

    constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(dataBytes => 2);

    type RegType is record
        data          : slv(15 downto 0);
        dataK         : slv(1 downto 0);
        dataDbSd      : slv(7 downto 0);
        dataDbSdK     : sl;
        dataTrigs     : slv(7 downto 0);
        dataTrigsK    : sl;
        cnt           : slv(31 downto 0);
        sdReadoutTrig : sl;
    end record;

    constant REG_INIT_C : RegType := (
        data          => (others => '0'),
        dataK         => (others => '0'),
        dataDbSd      => (others => '0'),
        dataDbSdK     => '0',
        dataTrigs     => (others => '0'),
        dataTrigsK    => '0',
        cnt           => (others => '0'),
        sdReadoutTrig => '0');


    constant NUM_AXIL_MASTERS_C : natural          := 1;
    constant AXIL_BASE_ADDR_C   : slv(31 downto 0) := (others => '0');

    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_C, 28, 24);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal dataClk : sl := '0';
    signal dataRst : sl := '1';
    signal axiClk  : sl := '0';
    signal axiRst  : sl := '1';

    signal axilWriteMaster : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
    signal axilWriteSlave  : AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C;
    signal axilReadMaster  : AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
    signal axilReadSlave   : AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C;

    signal axisMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
    signal axisSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C;

begin

    ---------------------------
    -- Generate clock and reset
    ---------------------------
    U_DataClkRst : entity surf.ClkRst
        generic map (
            CLK_PERIOD_G      => DATA_CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => dataClk,
            clkN => open,
            rst  => dataRst,
            rstL => open);

    U_AxiClkRst : entity surf.ClkRst
        generic map (
            CLK_PERIOD_G      => AXI_CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => axiClk,
            clkN => open,
            rst  => axiRst,
            rstL => open);

    --------------------------
    -- Design Under Test (DUT)
    --------------------------
    U_EvrDecoder : entity work.EvrDecoder
        generic map(
            TPD_G            => TPD_C,
            N_TRGS_G         => 2,
            AXIL_BASE_ADDR_G => AXIL_CONFIG_C(0).baseAddr
            )
        port map(
            -- Serial data input
            clk     => dataClk,
            data    => r.data,
            dataK   => r.dataK,
            dispErr => (others => '0'),  -- No errors
            decErr  => (others => '0'),
            rst     => dataRst,  -- Keep in reset until data valid (forces reset while GTY resetting)

            -- Trigger outputs
            trgs => open,

            -- Trigger to readout most recent received shared data via AXI stream
            sdReadoutTrig => r.sdReadoutTrig,

            -- AXI-Stream Interface (axisClk domain)
            axisClk    => axiClk,
            axisRst    => axiRst,
            -- axisMaster => axisMasters(EVR_SD_INDEX_C),
            -- axisSlave  => axisSlaves(EVR_SD_INDEX_C),
            axisMaster => axisMaster,
            axisSlave  => axisSlave,

            -- AXI-Lite register interface
            axilClk         => axiClk,
            axilRst         => axiRst,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave
            );

    comb : process (r, dataRst) is
        variable v : RegType;
    begin
        -- Latch the current value
        v := r;

        -- Reset the strobes
        v.sdReadoutTrig := '0';

        -- Check if increment the counter
        if (r.cnt /= x"0000FFFF") then

            -- Increment the counter
            v.cnt := r.cnt + 1;

            -- Generate data
            if r.cnt = 512 - 1 then
                -- Transmission start marker
                v.dataDbSd  := x"1C";
                v.dataDbSdK := '1';
            elsif (r.cnt >= 512) and (r.cnt < 1024) then
                if r.cnt(0) = '1' then
                    v.dataDbSd := r.cnt(7 downto 0);  -- Lower 8 bits of counter
                else
                    v.dataDbSd := (others => '1');    -- Set DB to all ones
                end if;
                v.dataDbSdK := '0';
            elsif r.cnt = 1024 then
                -- Transmission end marker
                v.dataDbSd  := x"3C";
                v.dataDbSdK := '1';
            else
                v.dataDbSd  := (others => '0');
                v.dataDbSdK := '0';
            end if;

            -- Compose complete data vector
            v.data  := v.dataDbSd & v.dataTrigs;
            v.dataK := v.dataDbSdK & v.dataTrigsK;

            -- Request frame readout
            if (r.cnt = 1024 + 512) then
                v.sdReadoutTrig := '1';
            end if;

            if (r.cnt = 2048 * 2 + 113) then
                v.sdReadoutTrig := '1';
            end if;

            if (r.cnt = 2048 * 3 + 11) then
                v.sdReadoutTrig := '1';
            end if;

            if (r.cnt = 2048 * 4 + 24) then
                v.sdReadoutTrig := '1';
            end if;

            if (r.cnt = 2048 * 6 + 1244) then
                v.sdReadoutTrig := '1';
            end if;

            if (r.cnt = 2048 * 7 + 1) then
                v.sdReadoutTrig := '1';
            end if;

            if (r.cnt = 2048 * 8 + 222) then
                v.sdReadoutTrig := '1';
            end if;

            if (r.cnt = 2048 * 9 + 1024) then
                v.sdReadoutTrig := '1';
            end if;

        end if;

        -- Synchronous Reset
        if (dataRst = '1') then
            v := REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (dataClk) is
    begin
        if (rising_edge(dataClk)) then
            r <= rin after TPD_C;
        end if;
    end process seq;

end testbed;
