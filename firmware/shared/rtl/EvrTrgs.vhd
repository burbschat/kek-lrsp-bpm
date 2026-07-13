library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;


entity EvrTrgs is
    generic (
        TPD_G    : time    := 1 ns;
        N_TRGS_G : integer := 16        -- Number of mappable trigger outputs
        );
    port (
        clk       : in sl;
        rst       : in sl;
        data      : in slv(7 downto 0);
        dataValid : in sl;
        dataK     : in sl;

        -- Trigger outputs. High level names should be better assigned in
        -- software, not firmware. So just use numbers here.
        trgs      : out slv(N_TRGS_G - 1 downto 0);
        eventCode : out slv(7 downto 0);

        -- AXI-Lite register interface
        axilClk         : in  sl                     := '0';
        axilRst         : in  sl                     := '0';
        axilReadMaster  : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
        axilReadSlave   : out AxiLiteReadSlaveType;
        axilWriteMaster : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
        axilWriteSlave  : out AxiLiteWriteSlaveType
        );
end entity EvrTrgs;

architecture rtl of EvrTrgs is

    -- Counters incremented on trigger of a given trigger line. Both
    -- synchronous to usr clock NOT axil clock!
    signal trgCounts           : Slv32Array(N_TRGS_G - 1 downto 0) := (others => (others => '0'));
    signal trgCountsResetsSync : slv(N_TRGS_G - 1 downto 0);

    signal eventCodeInt : slv(7 downto 0);

    signal syncVecEvMapIn  : slv(N_TRGS_G * 8 - 1 downto 0);
    signal syncVecEvMapOut : slv(N_TRGS_G * 8 - 1 downto 0);

    signal trgsEventMapSync        : Slv8Array(N_TRGS_G - 1 downto 0);
    signal trgsIgnoreIfKSync       : sl;
    signal trgsIgnoreIfInvalidSync : sl;
    signal axilRstSync             : sl;

    type RegType is record
        trgsIgnoreIfK       : sl;
        trgsIgnoreIfInvalid : sl;

        -- Map storing event code corresponding to each trigger line
        trgsEventMap : Slv8Array(N_TRGS_G - 1 downto 0);

        trgCountsResets : slv(N_TRGS_G - 1 downto 0);

        axilReadSlave  : AxiLiteReadSlaveType;
        axilWriteSlave : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        trgsIgnoreIfK       => '1',     -- Ignore if comma by default
        trgsIgnoreIfInvalid => '1',     -- Ignore if error by default

        -- Set to all ones instead zeros as the default value for no event is 0x00, which
        -- however is not ignored here. This could be deliberately ignored but perhaps
        -- someone wants to trigger on every receive cycle? Just leave it for now.
        trgsEventMap => (others => (others => '1')),

        trgCountsResets => (others => '1'),  -- Reset counter lines high to reset counters on axil reset

        axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

begin

    -- Assign internal signals to outputs
    eventCode <= eventCodeInt;

    -- One event code is 8 bit so each trigger line requires an 8 bit register
    -- to set the corresponding event. For 32 triggers we need 32 * 8 = 256
    -- register bits. Could have more, but for now the register interface will
    -- have registers for up to 32 triggers only (should be enough).
    -- assert N_TRGS_G <= N_TRGS_MAX_C report "N_TRGS_G must be <= 32 with current register mapping" severity failure;

    -- Process to extract trigger signals
    TRGS_PROC : process(clk)
        variable trgsVar      : slv(N_TRGS_G - 1 downto 0);
        variable newTrgCounts : Slv32Array(N_TRGS_G - 1 downto 0);
    begin
        if rising_edge(clk) then
            -- Initialize variables
            trgsVar      := (others => '0');
            newTrgCounts := trgCounts;  -- Init with current counts, later reset or increment, then assign back to signal

            -- When reset asserted, do not issue triggers but keep remaining
            -- logic (counter resets unaffected)
            if (not (rst = '1' or axilRstSync = '1')) then
                -- Check if data should be ignored or not. We want to try to ignore
                -- 'bad' data for triggers to avoid accidental firing I guess.
                if (not (trgsIgnoreIfKSync = '1' and dataK = '1'))
                    and (not (trgsIgnoreIfInvalidSync = '1' and dataValid = '0')) then
                    -- Check against all event codes in the triggers to events map
                    -- register. Will this result in very complicated logic? If so,
                    -- avoidable?
                    -- Synchronize eventMapSync register to clk to ensure
                    -- no accidental triggers which perhaps could happen if we
                    -- read this register at just the time it is changed by the
                    -- axil process.
                    for i in 0 to N_TRGS_G - 1 loop
                        if trgsEventMapSync(i) = data then
                            trgsVar(i)      := '1';
                            newTrgCounts(i) := newTrgCounts(i) + 1;  -- Increase corresponding counter
                        end if;
                    end loop;

                    -- TODO: I guess that assumes that lines never stay high in idle? Maybe not a true assumption here...
                    -- Update eventCode signal, but only if new good data received
                    eventCodeInt <= data;
                end if;
            end if;

            -- Trigger counts reset
            -- Could have this before or after the event code check.
            -- For now, before the check so that even in the reset
            -- cycle we can count a trigger if it occurs. This should
            -- be the more consistent choice as adding trigger counts
            -- between resets is ensured to actually equal the number
            -- of total triggers.
            for i in 0 to N_TRGS_G - 1 loop
                if trgCountsResetsSync(i) = '1' then
                    newTrgCounts(i) := (others => '0');  -- Use variable to control assignment order
                end if;
            end loop;

            -- Update counters of which some may have been reset or incremented
            trgCounts <= newTrgCounts;

            -- Assign trigger outputs. Do this every time as we want to reset them
            -- if no event code matched (strobe)
            trgs <= trgsVar;

        end if;
    end process TRGS_PROC;

    -- Synchronize event map from axil clock domain
    Gen_SyncVecEvMapIn : for i in 0 to N_TRGS_G-1 generate
        syncVecEvMapIn(7 + i*8 downto 0 + i*8) <= r.trgsEventMap(i);
        trgsEventMapSync(i)                    <= syncVecEvMapOut(7 + i*8 downto 0 + i*8);
    end generate Gen_SyncVecEvMapIn;

    U_SyncVecEvMap : entity surf.SynchronizerVector
        generic map(
            TPD_G   => TPD_G,
            WIDTH_G => N_TRGS_G * 8
            )
        port map(
            clk     => clk,
            rst     => rst,
            dataIn  => syncVecEvMapIn,
            dataOut => syncVecEvMapOut);

    -- Synchronize 'ignore if' registers
    U_SyncTrgsIgnoreIfK : entity surf.Synchronizer
        generic map(TPD_G => TPD_G)
        port map(
            clk     => clk,
            rst     => rst,
            dataIn  => r.trgsIgnoreIfK,
            dataOut => trgsIgnoreIfKSync);

    U_SyncTrgsIgnoreIfInvalid : entity surf.Synchronizer
        generic map(TPD_G => TPD_G)
        port map(
            clk     => clk,
            rst     => rst,
            dataIn  => r.trgsIgnoreIfInvalid,
            dataOut => trgsIgnoreIfInvalidSync);

    -- Synchronize axil reset
    U_AxilRstSync : entity surf.RstSync
        generic map (TPD_G => TPD_G)
        port map (
            clk      => clk,
            asyncrst => axilRst,
            syncRst  => axilRstSync);

    -- Synchronize counter reset from axi clock domain (register interface) to usr clock domain.
    -- Use one-shot synchronizer to make sure we don't accidentally keep resets on usr clock side
    -- high for multiple clock cycles which could lead to counts being lost if we keep a slow
    -- tally.
    -- TODO: The counters itself should also be synchronized? Not catching a signal
    -- as for reset strobes should be no problem but perhaps reading it during a transition
    -- might be? But how would the synchronizer resolve such an issue to begin with...
    U_SyncVecCounts : entity surf.SynchronizerOneShotVector
        generic map(
            TPD_G   => TPD_G,
            WIDTH_G => N_TRGS_G)
        port map(
            clk     => clk,
            rst     => rst,
            dataIn  => r.trgCountsResets,
            dataOut => trgCountsResetsSync);


    -- AXI-Lite register interface processes
    comb : process(axilReadMaster, axilWriteMaster, r, eventCodeInt, trgCounts)
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin
        -- Latch the current value
        v := r;

        -- Reset strobes
        v.trgCountsResets := (others => '0');

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        -- TODO: Decide addresses, AGAIN!
        axiSlaveRegister (axilEp, x"00", 0, v.trgsIgnoreIfK);
        axiSlaveRegister (axilEp, x"00", 2, v.trgsIgnoreIfInvalid);
        axiSlaveRegisterR (axilEp, x"04", 0, eventCodeInt);

        -- One event code is 8 bit so each trigger line requires an 8 bit register
        -- to set the corresponding event. Place at end of address space as the number
        -- of registers depends on generic and may change.
        for i in 0 to N_TRGS_G - 1 loop
            -- TODO: Check if integer division works as intended!
            axiSlaveRegister (axilEp, x"08" + conv_std_logic_vector((i / 4) * 4, 8), (i * 8) mod 32, v.trgsEventMap(i));
            -- Start at final 32 bit register of event to trigger mapping plus one register (offset by 4)
            axiSlaveRegisterR (axilEp, x"08" + conv_std_logic_vector(((N_TRGS_G - 1) / 4) * 4, 8) + x"04" + i * 4, 0, trgCounts(i));
            -- Ok this becomes silly at this point... Just wanted to see how far I can take this. I'm impressed if this works to begin with...
            axiSlaveRegister (axilEp, x"08" + conv_std_logic_vector(((N_TRGS_G - 1) / 4) * 4, 8) + x"04" + (N_TRGS_G - 1) * 4 + x"04" + (i / 32) * 4, i mod 32, v.trgCountsResets(i));
        end loop;

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Outputs

        axilWriteSlave <= r.axilWriteSlave;
        axilReadSlave  <= r.axilReadSlave;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (axilClk, axilRst) is
    begin
        if axilRst = '1' then
            r <= REG_INIT_C;
        elsif rising_edge(axilClk) then
            r <= rin after TPD_G;
        end if;
    end process seq;

end architecture rtl;
