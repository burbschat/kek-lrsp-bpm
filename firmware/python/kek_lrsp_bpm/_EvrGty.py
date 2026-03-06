import pyrogue as pr


class EvrGty(pr.Device):
    def __init__(
        self,
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)

        self.add(pr.RemoteVariable(
            name         = 'loopback',
            description  = 'GTY loopback mode',
            offset       = 0x0,
            bitSize      = 3,
            mode         = 'RW',
            hidden       = False,
        ))


        self.add(pr.RemoteVariable(
            name         = 'dummyData',
            description  = 'Dummy data to transmit for testing',
            offset       = 0x4,
            bitSize      = 8,
            mode         = 'RW',
            hidden       = False,
        ))


        self.add(pr.RemoteVariable(
            name         = 'dummyDataComma',
            description  = 'Comma to insert when transmitting dummy data for testing',
            offset       = 0x8,
            bitSize      = 8,
            mode         = 'RW',
            hidden       = False,
        ))


        self.add(pr.RemoteVariable(
            name         = 'trxRequestLP',
            description  = 'Set transceiver low power mode (only works if corresponding line is connected)',
            offset       = 0xA,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        # Offset 0x0001_0000 and above is axil translated DRP interface to GTY transceiver
