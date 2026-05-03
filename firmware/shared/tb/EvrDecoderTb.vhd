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

    constant CLK_PERIOD_C : time := 10 ns;
    constant TPD_C        : time := CLK_PERIOD_C/4;

    constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(dataBytes => 2);

    type RegType is record
        data         : slv(15 downto 0);
        dataValid    : sl;
        frameDone    : sl;
        cnt          : slv(11 downto 0);
        getFrameTrig : sl;
    end record;

    constant REG_INIT_C : RegType := (
        data         => (others => '0'),
        dataValid    => '0',
        frameDone    => '0',
        cnt          => (others => '0'),
        getFrameTrig => '0');


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
            CLK_PERIOD_G      => CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => dataClk,
            clkN => open,
            rst  => dataRst,
            rstL => open);

    U_AxiClkRst : entity surf.ClkRst
        generic map (
            CLK_PERIOD_G      => CLK_PERIOD_C/3.1415,  -- Make clocks more or less async
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
            usrClk  => dataClk,
            data    => (others => '1'),
            dataK   => (others => '0'),
            dispErr => (others => '0'),
            decErr  => (others => '0'),
            rst     => dataRst,  -- Keep in reset until data valid (forces reset while GTY resetting)

            -- Trigger outputs
            trgs => open,

            -- Trigger to readout most recent received shared data via AXI stream
            sdReadoutTrig => '0',

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
        v.frameDone    := '0';
        v.getFrameTrig := '0';

        -- Check if increment the counter
        if (r.cnt /= x"FFF") then

            -- Increment the counter
            v.cnt := r.cnt + 1;

            -- Generate data
            if r.cnt < 2048 then
                v.data      := r.data + 1;
                v.dataValid := '1';
            else
                v.data      := (others => '0');
                v.dataValid := '0';
            end if;

            -- Frame done issued half way through, to check continous frame
            -- recording and done flag functionality. Data will go on for
            -- another buffer length to allow for check of the buffer full
            -- frame end condition.
            if (r.cnt = 1023) then
                -- Set the flag
                v.frameDone := '1';
            end if;

            -- Check for the readout trigger event
            if (r.cnt = 1023) then
                -- Set the flag
                v.getFrameTrig := '1';
            end if;

        end if;

        -- Start hammering the trigger line to see if the module reacts
        -- correctly and starts next readout immediately after last one
        -- completed.
        if (r.cnt > 1024 + 512) then
            -- Set the flag
            v.getFrameTrig := '1';
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
