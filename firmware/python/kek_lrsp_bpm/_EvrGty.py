import pyrogue as pr
import kek_lrsp_bpm as rfsoc


class EvrGty(pr.Device):
    def __init__(
        self,
        *args,
        poll_interval=1,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)

        self.poll_interval = poll_interval

        self.add(pr.RemoteVariable(
            name         = 'qsfpModSelL',
            description  = 'QSFP module NOT select for i2c access',
            offset       = 0x0,
            bitOffset    = 0,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))


        self.add(pr.RemoteVariable(
            name         = 'qsfpResetL',
            description  = 'QSFP module NOT reset',
            offset       = 0x0,
            bitOffset    = 1,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'qsfpModPrsL',
            description  = 'QSFP module NOT present',
            offset       = 0x0,
            bitOffset    = 2,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'qsfpIntL',
            description  = 'QSFP module NOT interrupt signal',
            offset       = 0x0,
            bitOffset    = 3,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'qsfpLpMode',
            description  = 'QSFP module request low power mode',
            offset       = 0x0,
            bitOffset    = 4,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'ignoreQsfpModPrs',
            description  = 'Set to ignore qsfpModPrsL in ready signal logic (if not set, no ready until qsfpModPrsL=0)',
            offset       = 0x0,
            bitOffset    = 5,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        # Software resets
        self.add(pr.RemoteVariable(
            name         = 'softRst',
            description  = 'GTY full reset',
            offset       = 0x0,
            bitOffset    = 16,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'rxSoftRst',
            description  = 'GTY RX only reset',
            offset       = 0x0,
            bitOffset    = 17,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'txSoftRst',
            description  = 'GTY TX only reset',
            offset       = 0x0,
            bitOffset    = 18,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'resetGtSync',
            description  = 'GTY full reset signal readback',
            offset       = 0x0,
            bitOffset    = 19,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'gtRxUserResetSync',
            description  = 'GTY RX only reset signal readback',
            offset       = 0x0,
            bitOffset    = 19,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'gtTxUserResetSync',
            description  = 'GTY TX only reset signal readback',
            offset       = 0x0,
            bitOffset    = 19,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = False,
        ))

        for direction, offset in [("tx", 0x4), ("rx", 0x8)]:
            self.add(pr.RemoteVariable(
                name         = f'{direction}ResetDone',
                description  = f'GTY {direction} reset done',
                offset       = offset,
                bitOffset    = 0,
                bitSize      = 1,
                mode         = 'RO',
                pollInterval = self.poll_interval,
                hidden       = False,
            ))

            self.add(pr.RemoteVariable(
                name         = f'{direction}PmaResetDone',
                description  = f'GTY {direction} PMA reset done',
                offset       = offset,
                bitOffset    = 1,
                bitSize      = 1,
                mode         = 'RO',
                pollInterval = self.poll_interval,
                hidden       = False,
            ))

            self.add(pr.RemoteVariable(
                name         = f'{direction}UsrClkActive',
                description  = f'GTY {direction} user clock active',
                offset       = offset,
                bitOffset    = 2,
                bitSize      = 1,
                mode         = 'RO',
                pollInterval = self.poll_interval,
                hidden       = False,
            ))

            self.add(pr.RemoteVariable(
                name         = f'{direction}8b10bEn',
                description  = f'GTY {direction} 8b10b encoding enable',
                offset       = offset,
                bitOffset    = 3,
                bitSize      = 1,
                mode         = 'RW',
                hidden       = False,
            ))

            self.add(pr.RemoteVariable(
                name         = f'{direction}Polarity',
                description  = f'GTY {direction} polarity flip',
                offset       = offset,
                bitOffset    = 4,
                bitSize      = 1,
                mode         = 'RW',
                hidden       = False,
            ))


        self.add(pr.RemoteVariable(
            name         = f'rxCdrStable',
            description  = f'GTY rx clock data recovery stable',
            offset       = 0xC,
            bitOffset    = 0,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = f'rxDispErr',
            description  = f'GTY rx disparity error',
            offset       = 0xC,
            bitOffset    = 1,
            bitSize      = 2,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = f'rxDecErr',
            description  = f'GTY rx decode error',
            offset       = 0xC,
            bitOffset    = 3,
            bitSize      = 2,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = f'rxByteIsAligned',
            description  = f'GTY rx byte is aligned',
            offset       = 0xC,
            bitOffset    = 5,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        # Probably not useful as a register but whatever...
        self.add(pr.RemoteVariable(
            name         = f'rxByteRealign',
            description  = f'GTY rx byte realign strobe',
            offset       = 0xC,
            bitOffset    = 6,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        # Probably not useful as a register but whatever...
        self.add(pr.RemoteVariable(
            name         = f'rxCommaDet',
            description  = f'GTY rx comma detected strobe',
            offset       = 0xC,
            bitOffset    = 7,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = self.poll_interval,
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = f'rxCommaDetEn',
            description  = f'GTY rx comma detection enable',
            offset       = 0xC,
            bitOffset    = 8,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = f'rxMCommaAlignEn',
            description  = f'GTY rx align on minus comma enable',
            offset       = 0xC,
            bitOffset    = 9,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = f'rxPCommaAlignEn',
            description  = f'GTY rx align on plus comma enable',
            offset       = 0xC,
            bitOffset    = 10,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))


        self.add(pr.RemoteVariable(
            name         = f'evrTxModeReg',
            description  = f'Mode for transmitting',
            offset       = 0x10,
            bitOffset    = 0,
            bitSize      = 8,
            mode         = 'RW',
            hidden       = False,
            # These are encoding dependent and thus may depend on
            # implementation of enums in the firmware
            enum         = {
                0x0: 'RX_MIRROR',
                0x1: 'DUMMY',
                0x2: 'SILENT',
            },
        ))

        self.add(pr.RemoteVariable(
            name         = f'dummyData',
            description  = f'Dummy data to transmit in DUMMY mode',
            offset       = 0x10,
            bitOffset    = 8,
            bitSize      = 8,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = f'dummyDataComma',
            description  = f'Comma to be occasionally transmitted with dummy data in DUMMY mode',
            offset       = 0x10,
            bitOffset    = 16,
            bitSize      = 8,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'loopback',
            description  = 'GTY loopback mode',
            offset       = 0x14,
            bitOffset    = 0,
            bitSize      = 3,
            mode         = 'RW',
            hidden       = False,
        ))


        # Offset 0x0001_0000 and above is axil translated DRP interface to GTY transceiver.
        # Registers for DRP could be added here (preferably as a nested device).
