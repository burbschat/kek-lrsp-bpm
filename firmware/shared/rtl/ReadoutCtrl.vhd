library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;

entity ReadoutCtrl is
    generic (
        TPD_G : time := 1 ns);
    port (
        -- Trigger Ports
        trigIn          : in  sl;
        ringBufTrigOut  : out sl;       -- To ring buffer
        -- DSP Interface
        dspClk          : in  sl;
        dspRst          : in  sl;
        fineDelay       : out Slv4Array(3 downto 0);
        coarseDelay     : out Slv4Array(3 downto 0);
        -- AXI-Lite Interface (axilClk domain)
        axilClk         : in  sl;
        axilRst         : in  sl;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType;
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType);
end ReadoutCtrl;

architecture rtl of ReadoutCtrl is

    type StateType is (
        IDLE_S,
        ARMD_S,
        DELAY_S,
        DEGLITCH_S);

    type RegType is record
        -- Trigger outputs
        trigRingBufMainDly    : slv(23 downto 0);
        trigRingBufMainDlyCnt : slv(23 downto 0);
        trigRingBufMain       : sl;
        -- Trigger controls
        trigInArm             : sl;
        setKeepArm            : sl;
        deglitchCnt           : slv(11 downto 0);
        deglitchLen           : slv(11 downto 0);
        -- Trigger input signals
        trigInPolarity        : sl;
        trigIn                : sl;
        -- Trigger control
        softTrig              : sl;
        fineDelay             : Slv4Array(3 downto 0);
        coarseDelay           : Slv4Array(3 downto 0);
        axilReadSlave         : AxiLiteReadSlaveType;
        axilWriteSlave        : AxiLiteWriteSlaveType;
        -- Trigger state
        state                 : StateType;
        stateReg              : slv(7 downto 0);
    end record RegType;
    constant REG_INIT_C : RegType := (
        -- Trigger outputs
        trigRingBufMainDly    => (others => '0'),
        trigRingBufMainDlyCnt => (others => '0'),
        trigRingBufMain       => '0',
        -- Trigger controls
        trigInArm             => '0',
        setKeepArm            => '0',
        deglitchCnt           => (others => '0'),
        deglitchLen           => x"800",
        -- Trigger input signals
        trigInPolarity        => '0',
        trigIn                => '0',
        -- Trigger control
        softTrig              => '0',
        fineDelay             => (others => x"0"),
        coarseDelay           => (others => x"0"),
        axilReadSlave         => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave        => AXI_LITE_WRITE_SLAVE_INIT_C,
        state                 => IDLE_S,
        stateReg              => (others => '0'));

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal axilDspReadMaster  : AxiLiteReadMasterType;
    signal axilDspReadSlave   : AxiLiteReadSlaveType  := AXI_LITE_READ_SLAVE_EMPTY_DECERR_C;
    signal axilDspWriteMaster : AxiLiteWriteMasterType;
    signal axilDspWriteSlave  : AxiLiteWriteSlaveType := AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C;

begin

    U_AxiLiteAsync : entity surf.AxiLiteAsync
        generic map (
            TPD_G           => TPD_G,
            COMMON_CLK_G    => false,
            NUM_ADDR_BITS_G => 32)
        port map (
            -- Slave Interface (axiClk domain)
            sAxiClk         => axilClk,
            sAxiClkRst      => axilRst,
            sAxiReadMaster  => axilReadMaster,
            sAxiReadSlave   => axilReadSlave,
            sAxiWriteMaster => axilWriteMaster,
            sAxiWriteSlave  => axilWriteSlave,
            -- Master Interface (dspClk domain)
            mAxiClk         => dspClk,
            mAxiClkRst      => dspRst,
            mAxiReadMaster  => axilDspReadMaster,
            mAxiReadSlave   => axilDspReadSlave,
            mAxiWriteMaster => axilDspWriteMaster,
            mAxiWriteSlave  => axilDspWriteSlave);

    comb : process (axilDspReadMaster, axilDspWriteMaster, dspRst, trigIn, r) is
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin
        -- Latch the current value
        v := r;

        -- Reset strobes
        v.softTrig        := '0';
        v.trigInArm       := '0';
        v.trigRingBufMain := '0';

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilDspWriteMaster, axilDspReadMaster, v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the registers
        -------------------------

        axiSlaveRegister (axilEp, x"04", 0, v.softTrig);  -- Main Buffer

        -- Reserved: address: [0xC:0xF]
        for i in 0 to 3 loop
            axiSlaveRegister (axilEp, x"14", (8*i), v.fineDelay(i));
            axiSlaveRegister (axilEp, x"18", (8*i), v.coarseDelay(i));
        end loop;

        axiSlaveRegister (axilEp, x"20", 24, v.trigInPolarity);

        axiSlaveRegisterR(axilEp, x"24", 4, r.trigIn);

        axiSlaveRegister (axilEp, x"28", 0, v.trigInArm);
        axiSlaveRegister (axilEp, x"28", 2, v.setKeepArm);

        axiSlaveRegister (axilEp, x"2C", 0, v.trigRingBufMainDly);
        axiSlaveRegister (axilEp, x"30", 0, v.deglitchLen);

        axiSlaveRegisterR(axilEp, x"34", 0, r.stateReg);

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Select the PMOD Input and apply polarity correction
        v.trigIn := trigIn xor r.trigInPolarity;

        case r.state is

            when IDLE_S =>
                -- Check for re-arming the trigger
                if (r.trigInArm = '1') then
                    -- Transition to armed state
                    v.state := ARMD_S;
                end if;
                -- Software trigger does not require arming
                if (r.softTrig = '1') then
                    v.trigRingBufMainDlyCnt := r.trigRingBufMainDly;  -- Preset the counter
                    v.state                 := DELAY_S;
                end if;

            when ARMD_S =>
                -- Check for hardware trigger event or software trigger
                if (r.trigIn = '1') or (r.softTrig = '1') then
                    v.trigRingBufMainDlyCnt := r.trigRingBufMainDly;  -- Preset the counter
                    v.state                 := DELAY_S;
                end if;

            when DELAY_S =>
                -- Delay state waits for set delay before outputting trigger
                if (r.trigRingBufMainDlyCnt = 0) then
                    -- Output the trigger
                    v.trigRingBufMain := '1';
                    -- Transition to next state
                    if (r.setKeepArm = '1') then
                        -- Initialize the deglitch counter
                        v.deglitchCnt := r.deglitchLen;
                        -- Transition to deglitch state if auto re-arm enabled
                        v.state       := DEGLITCH_S;
                    else
                        -- Transition to idle otherwise
                        v.state := IDLE_S;
                    end if;
                else
                    -- Decrement the counter
                    v.trigRingBufMainDlyCnt := r.trigRingBufMainDlyCnt - 1;
                end if;

            when DEGLITCH_S =>
                -- Wait until trigIn is low for certain number of clock cycles,
                -- then transition back to armed state
                if (r.trigIn = '1') then
                    v.deglitchCnt := r.deglitchLen;
                else
                    v.deglitchCnt := r.deglitchCnt - 1;
                    if r.deglitchCnt = 0 then
                        v.state := ARMD_S;
                    end if;
                end if;

        end case;

        -- Update state register
        v.stateReg := conv_std_logic_vector(StateType'pos(r.state), r.stateReg'length);

        ----------------------------------------------------------------------

        -- Outputs
        axilDspWriteSlave <= r.axilWriteSlave;
        axilDspReadSlave  <= r.axilReadSlave;
        fineDelay         <= r.fineDelay;
        coarseDelay       <= r.coarseDelay;
        -- Ring buffer trigger output
        ringBufTrigOut    <= r.trigRingBufMain;

        -- Reset
        if (dspRst = '1') then
            v := REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (dspClk) is
    begin
        if rising_edge(dspClk) then
            r <= rin after TPD_G;
        end if;
    end process seq;

end rtl;
